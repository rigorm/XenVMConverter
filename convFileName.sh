#!/bin/sh

declare -a arr_ascii_allowed=( 45 48 49 50 51 52 53 54 55 56 57 65 66 67 68 69 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 95 97 98 99 100 101 102 103 104 105 106 \
                                107 108 109 110 111 112 113 114 115 116 117 118 119 120 121 122 )
#con_filename=$(echo "$1" | sed 's/ /_/g')
con_filename="$1"

con_new_filename=""
for i in $(seq 0 $((${#con_filename} - 1)));
do
	letter="${con_filename:$i:1}"
	dec=$(LC_CTYPE=C printf '%d' "'${letter}")

        if [ $dec -eq 32 ]; then
        	con_new_filename="${con_new_filename}_"
        else
		for q in ${arr_ascii_allowed[@]};
		do
			if [ "$q" = "$dec" ]; then
                		con_new_filename="${con_new_filename}${letter}"
			fi
		done
        fi
done

if [ ${#con_new_filename} -gt 255 ]; then
	echo "${con_new_filename:0:254}"
else
	echo "${con_new_filename}"
fi
