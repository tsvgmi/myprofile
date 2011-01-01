#!/bin/bash

if [ -z "$1" ]; then
        echo "No URL!"
        exit
fi

url=$1
shift

echo \"http://www.youtube.com/get_video?video_id=`wget -q -O - $url | grep fullscreenUrl | awk -F'video_id=' '{ print $2 }' | sed -e 's/ /_/g' | tr -d \'\; `\" | xargs mplayer $*

###
# The scipt above grabs the html source to the real stream (the .flv file), which youtube constantly alters. The "http://www.youtube.com/get_video?video_id=" is always the prefix -- and the script uses wget to d/l and append the rest of the 'full' url (which is very long and stupid).. an ex.; 

#mplayer #"http://www.youtube.com/get_video?video_id=L2SED6sewRw&l=2965&sk=GOT2L_qmpVJOx0w#rud5ycdyuWziPg1lcC&fmt_map=6%2F720000%2F7%2F0%2F0&t=OEgsToPDskLlf4ls3xB6V84dMYLu#ndws&hl=en&plid=AARTXK76vCTnvQ5#JAAAC6ADCAAA&sdetail=rv%253AL2S#ED6sewRw&tk=P4Lg#O65y-u5BllZJBsB_e2Gw-OVgaMp4a8prsHTahDhuPN_xsReW2Q%3D%3D&title=Greg Kroah 
# Hartman on the Linux Kernel"
# as you can see, there are blank spaces also that need to be cleaned up (blank # # spaces replaced with underscores). 


