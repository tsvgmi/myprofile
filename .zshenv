#echo "in zshenv - $PWD"
fpath=($fpath ~/func/auto)
autoload $(echo ~/func/auto/*)
