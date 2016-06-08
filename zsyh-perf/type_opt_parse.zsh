#!/usr/bin/env zsh

#
# OPTIMIZED VERSION WITH BASH SYNTAX THAT USES : len INSTEAD OF : len-start_pos
#

# -------------------------------------------------------------------------------------------------
# Copyright (c) 2010-2015 zsh-syntax-highlighting contributors
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without modification, are permitted
# provided that the following conditions are met:
#
#  * Redistributions of source code must retain the above copyright notice, this list of conditions
#    and the following disclaimer.
#  * Redistributions in binary form must reproduce the above copyright notice, this list of
#    conditions and the following disclaimer in the documentation and/or other materials provided
#    with the distribution.
#  * Neither the name of the zsh-syntax-highlighting contributors nor the names of its contributors
#    may be used to endorse or promote products derived from this software without specific prior
#    written permission.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR
# IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND
# FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR
# CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
# DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER
# IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT
# OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
# -------------------------------------------------------------------------------------------------
# -*- mode: zsh; sh-indentation: 2; indent-tabs-mode: nil; sh-basic-offset: 2; -*-
# vim: ft=zsh sw=2 ts=2 et
# -------------------------------------------------------------------------------------------------

zmodload zsh/zprof

alias want_to_call_something=":"

# Possible sorts are:
# default
# unknown-token
# reserved-word
# alias
# suffix-alias
# builtin
# function
# command
# precommand
# commandseparator
# hashed-command
# path
# path_prefix
# globbing
# history-expansion
# single-hyphen-option
# double-hyphen-option
# back-quoted-argument
# single-quoted-argument
# double-quoted-argument
# dollar-quoted-argument
# dollar-double-quoted-argument
# back-double-quoted-argument
# back-dollar-quoted-argument
# assign
# redirection
# comment
 
# Helper to deal with tokens crossing line boundaries.
-zplg-statica-save() {
  integer start=$1 end=$2
  local sort=$3

  # Having end<0 would be a bug
  (( end < 0 )) && return 
  # Having start<0 is normal with e.g. multiline strings
  (( start < 0 )) && start=0

  region_highlight+=("$start $end $sort")
}

# Wrapper around 'type -w'.
#
# Takes a single argument and outputs the output of 'type -w $1'.
#
# NOTE: This runs 'setopt', but that should be safe since it'll only ever be
# called inside a $(...) subshell, so the effects will be local.
-zplg-statica-type() {
  if (( $#options_to_set )); then
    setopt $options_to_set;
  fi
  LC_ALL=C builtin type -w -- $1 2>/dev/null
}

# Main syntax highlighting function.
-zplg-statica()
{
  if [[ -o path_dirs ]]; then
    integer path_dirs_was_set=1
  else
    integer path_dirs_was_set=0
  fi

  emulate -L zsh
  setopt localoptions extendedglob bareglobqual

  ## Variable declarations and initializations
  local start_pos=0 end_pos highlight_glob=true arg sort
  local in_array_assignment=false # true between 'a=(' and the matching ')'
  typeset -a ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR
  typeset -a ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS
  typeset -a ZSH_HIGHLIGHT_TOKENS_CONTROL_FLOW
  local -a options_to_set # used in callees
  local buf="$(<$1)"
  integer len="${#buf}"

  region_highlight=()

  if (( path_dirs_was_set )); then
    options_to_set+=( PATH_DIRS )
  fi
  unset path_dirs_was_set

  ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR=(
    '|' '||' ';' '&' '&&'
    '|&'
    '&!' '&|'
    # ### 'case' syntax, but followed by a pattern, not by a command
    # ';;' ';&' ';|'
  )
  ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS=(
    'builtin' 'command' 'exec' 'nocorrect' 'noglob'
    'pkexec' # immune to #121 because it's usually not passed --option flags
  )

  # Tokens that, at (naively-determined) "command position", are followed by
  # a de jure command position.  All of these are reserved words.
  ZSH_HIGHLIGHT_TOKENS_CONTROL_FLOW=(
    $'\x7b' # block
    $'\x28' # subshell
    '()' # anonymous function
    'while'
    'until'
    'if'
    'then'
    'elif'
    'else'
    'do'
    'time'
    'coproc'
    '!' # reserved word; unrelated to $histchars[1]
  )

  local this_word=':start:' next_word
  integer in_redirection
  for arg in ${(zZ+c+)buf}; do
    if (( in_redirection )); then
      (( --in_redirection ))
    fi
    if (( in_redirection == 0 )); then
      # Initialize $next_word to its default value.
      next_word=':regular:'
    else
      # Stall $next_word.
      :
    fi
    # $already_added is set to 1 to disable adding an entry to region_highlight
    # for this iteration.  Currently, that is done for "" and $'' strings,
    # which add the entry early so escape sequences within the string override
    # the string's color.
    integer already_added=0
    local style_override=""
    if [[ $this_word == *':start:'* ]]; then
      in_array_assignment=false
      if [[ $arg == 'noglob' ]]; then
        highlight_glob=false
      fi
    fi

    # advance $start_pos, skipping over whitespace in $buf.
    if [[ $arg == ';' ]] ; then
      # We're looking for either a semicolon or a newline, whichever comes
      # first.  Both of these are rendered as a ";" (SEPER) by the ${(z)..}
      # flag.
      #
      # We can't use the (Z+n+) flag because that elides the end-of-command
      # token altogether, so 'echo foo\necho bar' (two commands) becomes
      # indistinguishable from 'echo foo echo bar' (one command with three
      # words for arguments).
      local needle=$'[;\n]'
      integer offset=${${buf: start_pos: len}[(i)$needle]}
      (( start_pos += offset - 1 ))
      (( end_pos = start_pos + $#arg ))
    else
      ((start_pos+=(len-start_pos)-${#${${buf: start_pos: len}##([[:space:]]|\\[[:space:]])#}}))
      ((end_pos=$start_pos+${#arg}))
    fi

    if [[ -n ${interactive_comments+'set'} && $arg[1] == $histchars[3] ]]; then
      if [[ $this_word == *(':regular:'|':start:')* ]]; then
        sort="comment"
      else
        sort="unknown-token" # prematurely terminated
      fi
      -zplg-statica-save $start_pos $end_pos $sort
      already_added=1
      continue
    fi

    # Parse the sudo command line
    if (( ! in_redirection )); then
      if [[ $this_word == *':sudo_opt:'* ]]; then
        case "$arg" in
          # Flag that requires an argument
          '-'[Cgprtu]) this_word=${this_word//:start:/};
                       next_word=':sudo_arg:';;
          # This prevents misbehavior with sudo -u -otherargument
          '-'*)        this_word=${this_word//:start:/};
                       next_word+=':start:';
                       next_word+=':sudo_opt:';;
          *)           ;;
        esac
      elif [[ $this_word == *':sudo_arg:'* ]]; then
        next_word+=':sudo_opt:'
        next_word+=':start:'
      fi
    fi

    if [[ $this_word == *':start:'* ]] && (( in_redirection == 0 )); then # $arg is the command word
     if [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS:#"$arg"} ]]; then
      sort="precommand"
     elif [[ "$arg" = "sudo" ]]; then
      sort="precommand"
      next_word=${next_word//:regular:/}
      next_word+=':sudo_opt:'
      next_word+=':start:'
     else
      -zplg-statica-expand-path $arg
      local expanded_arg="$REPLY"
      #local res="$(-zplg-statica-type ${expanded_arg})"
      res="alias"
      () {
        # Special-case: command word is '$foo', like that, without braces or anything.
        #
        # That's not entirely correct --- if the parameter's value happens to be a reserved
        # word, the parameter expansion will be highlighted as a reserved word --- but that
        # incorrectness is outweighed by the usability improvement of permitting the use of
        # parameters that refer to commands, functions, and builtins.
        local -a match mbegin mend
        local MATCH; integer MBEGIN MEND
        if [[ $res == *': none' ]] && (( ${+parameters} )) &&
           [[ ${arg[1]} == \$ ]] && [[ ${arg:1} =~ ^([A-Za-z_][A-Za-z0-9_]*|[0-9]+)$ ]]; then
          #res="$(-zplg-statica-type ${(P)MATCH})"
          res="alias"
        fi
      }
      case $res in
        *': reserved')  sort="reserved-word";;
        *': suffix alias')
                        sort="suffix-alias"
                        ;;
        *': alias')     () {
                          integer insane_alias
                          case $arg in 
                            # Issue #263: aliases with '=' on their LHS.
                            #
                            # There are three cases:
                            #
                            # - Unsupported, breaks 'alias -L' output, but invokable:
                            ('='*) :;;
                            # - Unsupported, not invokable:
                            (*'='*) insane_alias=1;;
                            # - The common case:
                            (*) :;;
                          esac
                          if (( insane_alias )); then
                            sort="unknown-token"
                          else
                            sort="alias"
                            local aliased_command="${"$(alias -- $arg)"#*=}"
                            [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS:#"$aliased_command"} && -z ${(M)ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS:#"$arg"} ]] && ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS+=($arg)
                          fi
                        }
                        ;;
        *': builtin')   sort="builtin";;
        *': function')  sort="function";;
        *': command')   sort="command";;
        *': hashed')    sort="hashed-command";;
        *)              if _zsh_highlight_main_highlighter_check_assign; then
                          sort="assign"
                          if [[ $arg[-1] == '(' ]]; then
                            in_array_assignment=true
                          else
                            # assignment to a scalar parameter.
                            # (For array assignments, the command doesn't start until the ")" token.)
                            next_word+=':start:'
                          fi
                        elif [[ $arg[0,1] == $histchars[0,1] || $arg[0,1] == $histchars[2,2] ]]; then
                          sort="history-expansion"
                        elif [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR:#"$arg"} ]]; then
                          if [[ $this_word == *':regular:'* ]]; then
                            # This highlights empty commands (semicolon follows nothing) as an error.
                            # Zsh accepts them, though.
                            sort="commandseparator"
                          else
                            sort="unknown-token"
                          fi
                        elif [[ $arg == (<0-9>|)(\<|\>)* ]]; then
                          # A '<' or '>', possibly followed by a digit
                          sort="redirection"
                          (( in_redirection=2 ))
                        elif [[ $arg[1,2] == '((' ]]; then
                          # Arithmetic evaluation.
                          #
                          # Note: prior to zsh-5.1.1-52-g4bed2cf (workers/36669), the ${(z)...}
                          # splitter would only output the '((' token if the matching '))' had
                          # been typed.  Therefore, under those versions of zsh, BUFFER="(( 42"
                          # would be highlighted as an error until the matching "))" are typed.
                          #
                          # We highlight just the opening parentheses, as a reserved word; this
                          # is how [[ ... ]] is highlighted, too.
                          sort="reserved-word"
                          -zplg-statica-save $start_pos $((start_pos + 2)) $sort
                          already_added=1
                          if [[ $arg[-2,-1] == '))' ]]; then
                            -zplg-statica-save $((end_pos - 2)) $end_pos $sort
                            already_added=1
                          fi
                        elif [[ $arg == '()' || $arg == $'\x28' ]]; then
                          # anonymous function
                          # subshell
                          sort="reserved-word"
                        else
                          if _zsh_highlight_main_highlighter_check_path; then
                            sort="path"
                          else
                            sort="unknown-token"
                          fi
                        fi
                        ;;
      esac
     fi
    else # $arg is a non-command word
      case $arg in
        $'\x29') # subshell or end of array assignment
                 if $in_array_assignment; then
                   sort="assign"
                   in_array_assignment=false
                 else
                   sort="reserved-word"
                 fi;;
        $'\x7d') sort="reserved-word";; # block
        '--'*)   sort="double-hyphen-option";;
        '-'*)    sort="single-hyphen-option";;
        "'"*)    sort="single-quoted-argument";;
        '"'*)    sort="double-quoted-argument"
                 -zplg-statica-save $start_pos $end_pos $sort
                 _zsh_highlight_main_highlighter_highlight_string
                 already_added=1
                 ;;
        \$\'*)   sort="dollar-quoted-argument"
                 -zplg-statica-save $start_pos $end_pos $sort
                 _zsh_highlight_main_highlighter_highlight_dollar_string
                 already_added=1
                 ;;
        '`'*)    sort="back-quoted-argument";;
        [*?]*|*[^\\][*?]*)
                 $highlight_glob && sort="globbing" || sort="default";;
        *)       if false; then
                 elif [[ $arg[0,1] = $histchars[0,1] ]]; then
                   sort="history-expansion"
                 elif [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR:#"$arg"} ]]; then
                   if [[ $this_word == *':regular:'* ]]; then
                     sort="commandseparator"
                   else
                     sort="unknown-token"
                   fi
                 elif [[ $arg == (<0-9>|)(\<|\>)* ]]; then
                   sort="redirection"
                   (( in_redirection=2 ))
                 else
                   if _zsh_highlight_main_highlighter_check_path; then
                     sort="path"
                   else
                     sort="default"
                   fi
                 fi
                 ;;
      esac
    fi
    # if a style_override was set (eg in _zsh_highlight_main_highlighter_check_path), use it
    [[ -n $style_override ]] && sort=$ZSH_HIGHLIGHT_STYLES[$style_override]
    (( already_added )) || -zplg-statica-save $start_pos $end_pos $sort
    if [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_COMMANDSEPARATOR:#"$arg"} ]]; then
      next_word=':start:'
      highlight_glob=true
    elif
       [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_CONTROL_FLOW:#"$arg"} && $this_word == *':start:'* ]] ||
       [[ -n ${(M)ZSH_HIGHLIGHT_TOKENS_PRECOMMANDS:#"$arg"} && $this_word == *':start:'* ]]; then
      next_word=':start:'
    elif [[ $arg == "repeat" && $this_word == *':start:'* ]]; then
      # skip the repeat-count word
      in_redirection=2
      # The redirection mechanism assumes $this_word describes the word
      # following the redirection.  Make it so.
      #
      # The repeat-count word will be handled like a redirection target.
      this_word=':start:'
    fi
    start_pos=$end_pos
    (( in_redirection == 0 )) && this_word=$next_word
  done
}

# Check if $arg is variable assignment
_zsh_highlight_main_highlighter_check_assign()
{
    setopt localoptions extended_glob
    [[ $arg == [[:alpha:]_][[:alnum:]_]#(|\[*\])(|[+])=* ]]
}

# Check if $arg is a path.
_zsh_highlight_main_highlighter_check_path()
{
  -zplg-statica-expand-path $arg;
  local expanded_path="$REPLY"

  [[ -z $expanded_path ]] && return 1
  [[ -e $expanded_path ]] && return 0

  # Search the path in CDPATH
  local cdpath_dir
  for cdpath_dir in $cdpath ; do
    [[ -e "$cdpath_dir/$expanded_path" ]] && return 0
  done

  # If dirname($arg) doesn't exist, neither does $arg.
  [[ ! -e ${expanded_path:h} ]] && return 1

  # If this word ends the buffer, check if it's the prefix of a valid path.
  if [[ ${BUFFER[1]} != "-" && ${#BUFFER} == $end_pos ]] &&
     [[ $WIDGET != accept-* ]]; then
    local -a tmp
    tmp=( ${expanded_path}*(N) )
    (( $#tmp > 0 )) && style_override=path_prefix && return 0
  fi

  # It's not a path.
  return 1
}

# Highlight special chars inside double-quoted strings
_zsh_highlight_main_highlighter_highlight_string()
{
  setopt localoptions noksharrays
  local -a match mbegin mend
  local MATCH; integer MBEGIN MEND
  local i j k sort
  # Starting quote is at 1, so start parsing at offset 2 in the string.
  for (( i = 2 ; i < end_pos - start_pos ; i += 1 )) ; do
    (( j = i + start_pos - 1 ))
    (( k = j + 1 ))
    case "$arg[$i]" in
      '$' ) sort="dollar-double-quoted-argument"
            # Look for an alphanumeric parameter name.
            if [[ ${arg:$i} =~ ^([A-Za-z_][A-Za-z0-9_]*|[0-9]+) ]] ; then
              (( k += $#MATCH )) # highlight the parameter name
              (( i += $#MATCH )) # skip past it
            elif [[ ${arg:$i} =~ ^[{]([A-Za-z_][A-Za-z0-9_]*|[0-9]+)[}] ]] ; then
              (( k += $#MATCH )) # highlight the parameter name and braces
              (( i += $#MATCH )) # skip past it
            else
              continue
            fi
            ;;
      "\\") sort="back-double-quoted-argument"
            if [[ \\\`\"\$ == *$arg[$i+1]* ]]; then
              (( k += 1 )) # Color following char too.
              (( i += 1 )) # Skip parsing the escaped char.
            else
              continue
            fi
            ;;
      *) continue ;;

    esac
    -zplg-statica-save $j $k $sort
  done
}

# Highlight special chars inside dollar-quoted strings
_zsh_highlight_main_highlighter_highlight_dollar_string()
{
  setopt localoptions noksharrays
  local -a match mbegin mend
  local MATCH; integer MBEGIN MEND
  local i j k sort
  local AA
  integer c
  # Starting dollar-quote is at 1:2, so start parsing at offset 3 in the string.
  for (( i = 3 ; i < end_pos - start_pos ; i += 1 )) ; do
    (( j = i + start_pos - 1 ))
    (( k = j + 1 ))
    case "$arg[$i]" in
      "\\") sort="back-dollar-quoted-argument"
            for (( c = i + 1 ; c <= end_pos - start_pos ; c += 1 )); do
              [[ "$arg[$c]" != ([0-9xXuUa-fA-F]) ]] && break
            done
            AA=$arg[$i+1,$c-1]
            # Matching for HEX and OCT values like \0xA6, \xA6 or \012
            if [[    "$AA" =~ "^(x|X)[0-9a-fA-F]{1,2}"
                  || "$AA" =~ "^[0-7]{1,3}"
                  || "$AA" =~ "^u[0-9a-fA-F]{1,4}"
                  || "$AA" =~ "^U[0-9a-fA-F]{1,8}"
               ]]; then
              (( k += $#MATCH ))
              (( i += $#MATCH ))
            else
              if (( $#arg > $i+1 )) && [[ $arg[$i+1] == [xXuU] ]]; then
                # \x not followed by hex digits is probably an error
                sort="unknown-token"
              fi
              (( k += 1 )) # Color following char too.
              (( i += 1 )) # Skip parsing the escaped char.
            fi
            ;;
      *) continue ;;

    esac
    -zplg-statica-save $j $k $sort
  done
}

# Called with a single positional argument.
# Perform filename expansion (tilde expansion) on the argument and set $REPLY to the expanded value.
#
# Does not perform filename generation (globbing).
-zplg-statica-expand-path()
{
  # The $~1 syntax normally performs filename generation, but not when it's on the right-hand side of ${x:=y}.
  setopt localoptions nonomatch
  unset REPLY
  : ${REPLY:=${(Q)~1}}
}

-zplg-statica "$1"

print -rl "${region_highlight[@]}"

#zprof | head
