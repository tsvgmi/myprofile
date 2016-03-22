############################################################################
# File:        .profile
# Author:      tvuong
# Created:     Mon Apr 03 12:15:37 PDT 2006
# Description:
############################################################################
mtty=$(tty)
if [ $? -eq 0 ]; then
  if [ ! "$ZSH_VERSION" ]; then
    exec zsh --login
  fi
  if [ "$mtty" == "/dev/tty1" ]; then
    case $(uname) in
    CYGWIN*) ;;
    *)       exec startx ;;
    esac
  fi
  [ -f ~/.profile_cm   ] && . ~/.profile_cm
  [ -r ~/.alias.man ]    && . ~/.alias.man
  [ -f ~/.profile_priv ] && . ~/.profile_priv
fi

# MacPorts Installer addition on 2011-08-22_at_00:42:28: adding an appropriate PATH variable for use with MacPorts.
export PATH=/opt/local/bin:/opt/local/sbin:$PATH
# Finished adapting your PATH environment variable for use with MacPorts.

unset LD_LIBRARY_PATH

PATH=$PATH:/usr/local/bin:/usr/local/sbin

##
# Your previous /Users/tvuong/.bash_profile file was backed up as /Users/tvuong/.bash_profile.macports-saved_2013-08-20_at_14:27:36
##

CDPATH=$CDPATH:~/work:~/projects

. ~/.rvm/scripts/rvm

export PATH="$HOME/.rvm/bin:$PATH" # Add RVM to PATH for scripting

export PATH="$HOME/.rbenv/bin:$PATH"
eval "$(rbenv init -)"

CDPATH=$CDPATH:~/work:~/projects

# The next line updates PATH for the Google Cloud SDK.
export PATH=/Users/tvuong/google-cloud-sdk/bin:$PATH

# The next line enables bash completion for gcloud.
source /Users/tvuong/google-cloud-sdk/arg_rc

test -e "${HOME}/.iterm2_shell_integration.bash" && source "${HOME}/.iterm2_shell_integration.bash"
