############################################################################
# File:        .profile
# Author:      tvuong
# Created:     Mon Apr 03 12:15:37 PDT 2006
# Description:
############################################################################
date
[ -f ~/.profile_cm   ] && . ~/.profile_cm
[ -r ~/.alias.man ] && . ~/.alias.man
[ -f ~/.profile_priv ] && . ~/.profile_priv
case $DISPLAY in
:0*) xset -r ;;
esac
date
