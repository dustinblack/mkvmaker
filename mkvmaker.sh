#  mkvmaker simple VOB to MKV transcoder script v0.98
#
#  Copyright (C) 2015  Dustin Louis Black (dustin at redshade dot net)
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License along
#  with this program; if not, write to the Free Software Foundation, Inc.,
#  51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.

mplayer="/usr/bin/mplayer"
mencoder="/usr/bin/mencoder"

function _usage {
  cat <<END

VOB file transcoder
  Creates a quality matroska .mkv file with x264 compressed video, AAC 
  compressed stereo audio, and preserved AC3 Dolby surround audio

Usage: $(basename "${0}") [-c] [-d] [-h] [-t] [-T] <file path>

  -b : tune for high definition (blu-ray)

  -c <crop value> : formatted w:h:x:y (optional - auto-detected if omitted)
                    get this from the output of:
                    'mplayer <file path> -vf cropdetect'

  -d : cleanup (delete) temporary files (default is don't delete)
       deletes all temporary files after mkv is fully processed
 
  -h : show this help message

  -t <f|a> : for (f)ilm or (a)nimation source (film assumed if omitted)
             applies appropriate transcoder tunings

  -T : just do a test run (optional)
       will output the commands to be run without executing them

  <file path> : the path to the input vob file (required)

END
}

while getopts ":bc:dht:T" opt; do
case ${opt} in
  b)
    bluray=1
    ;;
  c)
    if [[ ${crop} ]] ; then
      echo "ERROR: Option repeated: -${OPTARG}" >&2
      _usage
      exit 1
    else
      crop=${OPTARG}
    fi
    ;;
  d)
    delete_temp=1
    ;;
  h)
    _usage
    exit 1
    ;;
  t)
    if [[ ${tune_type} ]] ; then
      echo "ERROR: Option repeated: -${OPTARG}" >&2
      _usage
      exit 1
    elif [[ ${OPTARG} == "a" ]] ; then
      tune_type="animation"
    else
      tune_type="film"
    fi
    ;;
  T)
    just_test=1
    ;;
  \?)
    echo "ERROR: Invalid option -${OPTARG}" >&2
    _usage
    exit 1
    ;;
  :)
    echo "ERROR: Option -${OPTARG} requires an argument." >&2
    _usage
    exit 1
    ;;
  esac
done

echo ""

shift $((OPTIND -1))

if [[ ! ${1} ]] ; then
  echo "ERROR: No input file provided" >&2
  _usage
  exit 1
else
  vobfile=${1}
fi

if [[ ${just_test} ]] ; then
  echo -e "!!! THIS IS JUST A TEST RUN !!!\n"
fi

echo -e "Input filename is: $(basename "${vobfile}")\n"

if [[ ! ${tune_type} ]] ; then
  echo -e "Option -t (tune type) not specified; assuming (f)ilm\n"
  tune_type="film"
fi

echo -e "Tuning for ${tune_type}...\n"

# Set probe crop command
#probecrop_cmd="mplayer -ao null -ss 60 -frames 500 -vf cropdetect -vo null "${vobfile}" 2>/dev/null | awk -F '[()]' '{print $2}' | uniq | grep -Ev 'End of file' | tail -2 | awk -F= '{print $2}'"
#probecrop_cmd="mplayer -ao null -ss 60 -frames 500 -vf cropdetect -vo null ${vobfile} 2>/dev/null | grep crop | tail -1 | awk -F= '{print \$2}' | awk -F\) '{print \$1}'"
probecrop_cmd="${mplayer} -ao null -ss 60 frames 500 -vf cropdetect -vo null vobs/maze_runner-scorch_trials.vob 2>/dev/null | grep VO | tail -1 | awk -F= '{print \$2}' | awk '{print \$2}'"

if [[ ! ${crop} ]] ; then
# Auto-grab video crop value
  echo "Option -c (crop) not specified"
  echo "Probing video crop value... this may take a minute..."
  if [[ ${just_test} ]] ;  then
    echo "${probecrop_cmd}"
  else
    eval crop=\`${probecrop_cmd}\`
    echo -e "Crop is: ${crop}\n"
  fi
fi


name="$(basename "${vobfile}" .vob)"

# Set bitrate
if [[ ${bluray} ]] ; then
  bitrate=2400
else
  bitrate=1400
fi

# Set mencoder base command
#menc_cmd="mencoder ${vobfile} -sid 0 -forcedsubsonly -passlogfile ${name}.log -vf pullup,softskip,crop=${crop},hqdn3d=2:1:2,harddup -ofps 24000/1001 -alang en -oac faac -faacopts br=192:object=2 -ovc x264 -x264encopts bitrate=${bitrate}:tune=${tune_type}:bframes=4:pass="
menc_cmd="${mencoder} ${vobfile} -sid 0 -forcedsubsonly -vf pullup,softskip,crop=${crop},hqdn3d=2:1:2,harddup -ofps 24000/1001 -alang en -oac faac -faacopts br=192:object=2 -ovc x264 -x264encopts preset=slow:crf=25:bitrate=${bitrate}:tune=${tune_type}:bframes=4:subq=8:frameref=6:partitions=all"


#echo -e "\nStarting Transcode Pass 1..."
#tpass1="${menc_cmd}1:subq=1:frameref=1 -o /dev/null"
#if [[ ${just_test} ]] ; then
  #echo "${tpass1}"
#else
  #${tpass1}
#fi

#echo -e "\nStarting Transcode Pass 2..."
echo -e "\nStarting Transcode..."
#tpass2="${menc_cmd}2:subq=8:frameref=6:partitions=all -o ${name}.avi"
tpass2="${menc_cmd} -o ${name}.avi"
if [[ ${just_test} ]] ; then
  echo "${tpass2}"
else
  ${tpass2}
fi

echo -e "\nDumping Dolby AC3 Audio..."
ac3dump="${mplayer} ${vobfile} -alang en -dumpaudio -dumpfile ${name}.ac3"
if [[ ${just_test} ]] ; then
  echo "${ac3dump}"
else
  ${ac3dump}
fi

echo -e "\nMerging MKV Container..."
merge="mkvmerge -o ${name}.mkv ${name}.avi ${name}.ac3"
setlang="mkvpropedit ${name}.mkv --edit track:a1 --set name='English Stereo' --set language=eng --edit track:a2 --set name='English AC3' --set language=eng"
if [[ ${just_test} ]] ; then
  echo "${merge}"
  echo "${setlang}"
else
  ${merge}
  eval "${setlang}"
fi

if [[ ${delete_temp} ]] ; then
  echo -e "\nCleaning Up..."
  cleanup="rm -f ${name}.log* ${name}.avi ${name}.ac3"
  if [[ ${just_test} ]] ; then
    echo "${cleanup}"
  else
    ${cleanup}
  fi
fi

if [[ ${just_test} ]] ; then
  echo -e "\n!!! THIS IS JUST A TEST RUN !!!\n"
fi

