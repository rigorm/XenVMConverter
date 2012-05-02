#!/bin/bash


#########################################
# Set default variables
#########################################
user=""
password=""
ip=""
uuid=""
image="image1"
vmname=""
lvm=0
force=0
xenserver=0
help=0
vg=""
vmlist=""
vmlistvalid=0
mode=""
uuidlist=""
LIST=( --user --password --ip --uuid --image --lvm --vg --force --xenserver --vmname --vmlist --help )
#REQUIRED=( --user --password --ip --uuid )
#########################################


#################################################################
# apps needed (pretty streat forward)				#
# everything should be installed on every distro, except for lvm#
# --------------------------------------------------------------#
#								#
#	grep							#
#	lvm	(if installing to a VG.)			#
#	stat	(again, only used in the lvm routine)		#
#	dd							#
#	curl							#
#	tar							#
#	test							#
#	python	(everything around the snapshot routine)	#
#################################################################


ARGS=("$@")
REQ_STATE=true
CUR_DIR="$(pwd)"
LVM_BIN="/sbin/lvm"
WORKFILE=".tmp_current_uuid"

if [ -f ${PWD}/${WORKFILE} ]; then
	rm -f ${PWD}/${WORKFILE}
fi


# flag validation stage --------------------------------------------------------------------------------------------------------------------------------
for (( i=0;i<${#ARGS[@]};i++)); do
	arg=${ARGS[$i]}


	for q in ${LIST[@]}
	do
		if [ "$q" = "$arg" ]; then
			var=$(echo "${arg}" | sed 's/--//g')
			((i++))
			if [ "$(echo "${ARGS[$i]}" | grep -c "\-\-")" = "1" ] || [ "${i}" = "${#ARGS[@]}" ]; then
				eval $var=1
				#echo "${var} = 1"
				((i--))
				break
			else
				eval $var="$(echo "${ARGS[$i]}" | sed 's/ /\\ /g')"
				break
			fi
		fi
	done
done



if [ $help -eq 1 ]; then
	cat << EOF
		#----------------------------------------------------------
		# XenVmConverter : command reference
		#----------------------------------------------------------

		Parameters: (prameters with a * are required)
			--ip <ipaddr>		: xenserver's IP (or pool master's in xenserver mode)
			--user <user>		: the xenserver's user (usually root) (*)
			--password <passwd>	: the xenserver's password (*)
			--uuid <uuid>		: a VM's UUID (when stopped) OR a snapshot UUID
			--help			: this text (dah!)
			--lvm			: activate lvm mode (import image into LVM)
			--vg <vg name>		: in lvm mode, give the volume group name
			--force			: in lvm mode, delete the LV first
			--xensource		: activate xenserver auto snapshot/batch export
			--vmlist <path/list>	: text file with a list of VM names
			--vmname <name>		: a single VM name
			--image <image name>	: when in standalone, the .img file, when in LVM, the LV's name. Destination file will be in $pwd/images

		when using:
			--lvm:
				--image <image name> 	: will be the name of the LV (logical volume) name
				--vg <vg name>		: the Volume group name (without the /dev/ part) make sure the VG is visable/active
				--force			: Will delete the LV if it exist before importing

			--xenserver (create a snapshot of the vm first / enable batch mode):
				--ip <ipaddr>		: this need to be the master pool address (when in pool mode)
				--vmname <VM name>	: The virtual server's name label (note: use double quotes and there are spaces in the name)
				--vmlist <path/list>	: use a text file (one VM name per line) to do in bach mode
				(note #1: use --vmname OR --vmlist but not both)
				(note #2: this mode could fail if you have multiple interfaces and/or bonded. If you have multiple interfaces,
					  it will use the first one that has a IP and is not the management interface.

			standalone, you need:
				--ip	(the xenserver's IP. (not the pool master's. Pool master IP only when in --xenserver mode))
				--user
				--password
				--uuid	(make sure the VM is stopped OR you are using a snapshot)
				--image optional(when not used, you will get a image1.img file)

EOF
	exit 0
fi

image="$(${CUR_DIR}/convFileName.sh "${image}")"
IMAGE_NAME="${image}.img"



# Validaion area ---------------------------------------------------------------



# XenServer mode
if [ $xenserver -eq 1 ]; then
	xenserverip=$ip
	if [ "$vmlist" != "" ] && [ "$vmname" = "" ]; then
		if [ ! -f $vmlist ]; then
			echo "[Error]: --vmlist file not found ${vmlist}"
			exit 1
		else
			if [ $lvm -eq 1 ]; then
				echo "Using the vmlist (/w LVM): LVs will be named image1, image2, imageX and so on."
				echo "Please rename your LVs with lvrename after job is finished"

			else
				echo "Using the vmlist (/wo LVM): the files will be named image1, image2, imageX and so on."
				echo "Please rename afterward"
			fi
			vmlistvalid=1
			image="image_tmp"
			cat ${vmlist} > ${PWD}/${WORKFILE}
		fi
		REQUIRED=( --ip --user --password --vmlist )
	elif [ "$vmlist" = "" ] && [ "$vmname" != "" ]; then
		REQUIRED=( --ip --user --password --vmname )
		echo "${vmname}" > ${PWD}/${WORKFILE}
	else
		REQUIRED=( --ip --user --password --vmname --vmlist )
	fi
	mode="xenserver"
else
	mode="standalone"
	REQUIRED=( --ip --user --password --uuid )
	echo "${uuid}" > ${PWD}/${WORKFILE}
fi

# LVM mode
if [ $lvm -eq 1 ]; then
	REQUIRED_LVM=( --image --vg )
	if [ "$mode" != "" ]; then
		mode="$mode and LVM"
	fi
	REQUIRED=( ${REQUIRED[@]} ${REQUIRED_LVM[@]} )
fi

# Validate everything
for w in ${REQUIRED[@]}
do
	var=$(echo $w | sed 's/--//g')
	if [ "${!var}" = "" ]; then
		echo "[Error] Argument $w cannot be empty in ${mode} mode"
		REQ_STATE=false
	fi
done

if [ $REQ_STATE = false ]; then
	exit 1
fi
#-------------------------------------------------------------------------------------------------------------------------------------------------------


#####------ The loop for --vmlist could start here ------#####

cat ${PWD}/${WORKFILE} | while read LINE ; do

	uuid="${LINE}"
	echo "Working on : $uuid"

	if [ $vmlistvalid -eq 1 ]; then
		image="$(${CUR_DIR}/convFileName.sh "${LINE}")"
		IMAGE_NAME="${image}.img"
		vmname="${LINE}"
	fi

# Preparing work dir and destination dir -----------------------------
if [ ! -d "images" ]; then
	mkdir images
fi

if [ ! -d "t" ]; then
	mkdir t
else
	echo -n "Removing old work dir..."
	rm -rf t
	mkdir t
	echo "done"
fi

cd t
#---------------------------------------------------------------------





# Validating if XenServer stage active -------------------------------
xenserver_mount=0
if [ $xenserver -eq 1 ]; then
	echo -n "(XenServer) Creating snapshot..."
	if [ "${vmname}" != "" ]; then
		data=$(python ${CUR_DIR}/CreateSnapshot.py https://${xenserverip} ${user} ${password} "${vmname}")
		#echo "XenServer data: ${data}"
		data_status=$(echo $data | awk -F\| '{print $1}')
		if [ "${data_status}" = "Success" ]; then
			uuid=$(echo $data | awk -F\| '{print $2}')
			ip=$(echo $data | awk -F\| '{print $3}')
			xenserver_mount=1
			echo $data_status
		else
			echo ""
			echo -n "Failed to create snapshot: "
			echo $(echo $data | awk -F\| '{print $2}')
			echo "exiting"
			exit 1
		fi
	else
		echo "missing --vmname flag."
			exit 1
	fi
fi


echo -n "Stage #1: fetch (Citrix) Xenserver VM export..."
STAGE_1=$(curl -kfsu ${user}:${password} "https://${ip}/export?uuid=${uuid}" -o - | tar -xf - > /dev/null 2>&1 )
echo "done."


if [ $xenserver -eq 1 ] && [ $xenserver_mount -eq 1 ]; then
	data=$(python ${CUR_DIR}/RemoveSnapshot.py https://${xenserverip} ${user} ${password} "${vmname}")
	data_status=$(echo $data | awk -F\| '{print $1}')
	if [ "${data_status}" = "True" ]; then
		echo "(XenServer) Snapshot deleted successfully."
	else
		echo "(xenServer) Unable to delete snapshot, please remove it manually."
	fi
fi


echo -n "Stage #2: Convert to (open source) Xen image..."

REF_DIR=$(ls | grep "Ref:")
if [ "$REF_DIR" = "" ]; then
	echo "Woups ! no Ref directory found"
	exit 1
fi

cd "$REF_DIR"

dd if=/dev/zero of=blank bs=1024 count=1k > /dev/null 2>&1
test -f ../${IMAGE_NAME} && rm -f ../${IMAGE_NAME}
touch ../${IMAGE_NAME}

max=$(ls ???????? | sort | tail -n1)

CHUNK=$(($(echo $max | sed 's/0*//') / 10))
CHUNK_NUM=0
echo -n "$((CHUNK_NUM * 10))% "

for i in `seq 0 $max`; do
        fn=`printf "%08d" $i`
        if [ -f "$fn" ]; then
                cat $fn >> ../${IMAGE_NAME}
        else
                cat blank >> ../${IMAGE_NAME}
        fi
	if [ $i -gt $(($CHUNK * $CHUNK_NUM)) ]; then
		CHUNK_NUM=$(($CHUNK_NUM + 1))
		echo -n "$((CHUNK_NUM * 10))% "
	fi

done

echo "Done."



if [ $lvm -ne 1 ]; then
	echo "Stage #3: Move $(pwd)/${IMAGE_NAME} to ${CUR_DIR}/images/"
fi

mv ../${IMAGE_NAME} ${CUR_DIR}/images/
cd ${CUR_DIR}
rm -rf t


if [ $lvm -eq 1 ]; then

	#LVM is active so we need to transfer it.
	# The ${image name is used for the LV name.}
	# steps: (1)check if LVM is installed, (2)check free VG space, (3)check if LV exist and if not, (4)get file size and create same LV space

	# step 1

	if [ ! -f ${LVM_BIN} ]; then
		echo "LVM not installed"
		exit 1
	fi

	# step 2
	# Size is in bytes
	VG_FREE_SPACE=$(${LVM_BIN} vgs ${vg} -o vg_free --noheadings --unbuffered --units b --nosuffix > /dev/stdout 2>>1 | sed 's/ //g' | tail -n1)
	IS_LV=$(${LVM_BIN} lvs -o lv_name --noheadings --unbuffered --units b --nosuffix /dev/${vg}/${image} > /dev/stdout 2>>1 | sed 's/ //g' | tail -n1)
	if [ "${IS_LV}" != "" ] && [ "${IS_LV}" = "${image}" ] && [ $force = 1 ]; then
		echo -n "Logical volume found and forced active so deleting volume..."
		${LVM_BIN} lvremove -f /dev/${vg}/${image} > /dev/null 2>&1
		VG_FREE_SPACE=$(${LVM_BIN} vgs ${vg} -o vg_free --noheadings --unbuffered --units b --nosuffix > /dev/stdout 2>>1 | sed 's/ //g' | tail -n1)
        	IS_LV=$(${LVM_BIN} lvs -o lv_name --noheadings --unbuffered --units b --nosuffix /dev/${vg}/${image} > /dev/stdout 2>>1 | sed 's/ //g' | tail -n1)
		echo "done."
	fi
	if [ "${IS_LV}" != "" ] || [ "${IS_LV}" = "${image}" ]; then
		echo "Logical volume present"
		exit 1
	else
		echo "Logical volume dosent exist. Looking into it..."
		imagesize=$(stat --printf="%s" ${CUR_DIR}/images/${IMAGE_NAME})
		if [ $((${VG_FREE_SPACE} - ${imagesize})) -gt 0 ]; then
			echo -e "Free space on volume group ${vg}\nCreating Logical volume"
			${LVM_BIN} lvcreate --size ${imagesize}b --name ${image} ${vg} > /dev/null 2>&1
			echo -n "Transfering image file to logical partition (this may take a while)..."
			dd if=${CUR_DIR}/images/${IMAGE_NAME} of=/dev/${vg}/${image} bs=4M > /dev/null 2>&1
			rm -f ${CUR_DIR}/images/${IMAGE_NAME}
			echo "done."
		else
			echo "Not enough space on volume group. Leaving image file in ${CUR_DIR}/image/${IMAGE_NAME}"
			echo "Please make some space then dd the ${IMAGE_FILE}.img into the newly created LV"
			exit 1
		fi
	fi
fi

if [ $vmlistvalid -eq 1 ]; then
	echo -e "\n\r"
fi

#####------ The loop for --vmlist could end here ------#####

done

echo "All tasks finshed"

