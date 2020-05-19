#!/bin/bash
###############################################################################
#
#          Dell Inc. PROPRIETARY INFORMATION
# This software is supplied under the terms of a license agreement or
# nondisclosure agreement with Dell Inc. and may not
# be copied or disclosed except in accordance with the terms of that
# agreement.
#
# Copyright (c) 2017 Dell Inc. All Rights Reserved.
#
# Module Name:
#
#   dcism-setup.sh
#
#
# Abstract/Purpose:
#
#   Interactive Custom Install Script to cutomize the iDRAC Service Module
#   RPM Package install.
#   This interactive script will enable the user to choose the optional
#   features and make them available on the local machine.
#
# Environment:
#
#   Linux
#
###############################################################################
# Operating system ("OS") types.
# These are the return values for the following function:
#     GetOSType
#
GBL_OS_TYPE_ERROR=0
GBL_OS_TYPE_UKNOWN=1
GBL_OS_TYPE_SLES10=2
GBL_OS_TYPE_RHEL5=3
GBL_OS_TYPE_SLES11=4
GBL_OS_TYPE_RHEL6=5
GBL_OS_TYPE_RHEL7=6
GBL_OS_TYPE_SLES12=7
GBL_OS_TYPE_UBUNTU16=8
GBL_OS_TYPE_SLES15=9
GBL_OS_TYPE_UBUNTU18=10

GBL_OS_TYPE_STRING=$GBL_OS_TYPE_UKNOWN
PATH_TO_RPMS_SUFFIX=""

#Error Handling
UPDATE_SUCCESS=0
UPDATE_FAILED=1
UPDATE_NOT_REQD=2
UPDATE_FAILED_NEWER_VER_AVAILABLE=3
UPDATE_PREREQ_NA=4
SERVICE_FAILED_TO_START=5
ERROR=6
UNINSTALL_FAILED=7

BASEDIR=`dirname $0`
SCRIPT_SOURCE="installer"
SYSIDFILEPATH=""
LICENSEFILEPATH=""
LICENSEFILE="$BASEDIR/prereq/license_agreement.txt"
INSTALL_CONFIG="$BASEDIR/install.ini"
FEATURE_COUNT=0
OPTION_COUNT=1
PREDEFINE_OPTION=0
IDRAC_HARD_RESET_STR="iDRAC Hard Reset"
SUPPORT_ASSIST_STR="Support Assist"
FULLPOWER_CYCLE_STR="Full Power Cycle"

if [ -f "$INSTALL_CONFIG" ]; then
IFS=$'\r\n'
FEATURE_COUNT=`grep -i "^dc*" "$INSTALL_CONFIG"|grep -v "triggered"|wc -l`
OPTION_COUNT=`expr $FEATURE_COUNT + 4`

DCISM_FEATURE_ARRAY=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $2}'))
DCISM_FEATURE_ARRAY+=("$IDRAC_HARD_RESET_STR")
DCISM_FEATURE_ARRAY+=("$SUPPORT_ASSIST_STR")
DCISM_FEATURE_ARRAY+=("$FULLPOWER_CYCLE_STR")
DCISM_FEATURE_ARRAY+=("All Features")
DCISM_TRIGGERABLE_FEATURE_ARRAY=($(grep -v ^# "$INSTALL_CONFIG" |grep -i "triggered"|awk -F"|" '{print $2}'))
DCISM_FEATURES_ENABLED_ARRAY=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $4}'))
DCISM_FEATURES_ENABLED_ARRAY+=("true")
DCISM_FEATURES_ENABLED_ARRAY+=("true")
DCISM_FEATURES_ENABLED_ARRAY+=("true")
DCISM_FEATURES_ENABLED_ARRAY+=("false")
DCISM_SECTIONS=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $1}'))
for i in "${!DCISM_FEATURE_ARRAY[@]}"; do 
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "iDRAC access via Host OS" ]; then
          IBIA_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "Access via GUI, WS-man, Redfish, Remote Racadm " ]; then
          OS2IDRAC_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "In-band SNMP Traps" ]; then
          SNMPTRAP_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "Access via SNMP Get" ]; then
          SNMPGET_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "iDRAC Hard Reset" ]; then
          IDRAC_HARD_RESET_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "Support Assist" ]; then
          SUPPORT_ASSIST_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "Full Power Cycle" ]; then
          FULLPOWER_CYCLE_INDEX=$i
      fi
      if [ "${DCISM_FEATURE_ARRAY[$i]}" == "All Features" ]; then
          ALLFEATURES_INDEX=$i
      fi
done
SHORTOPTS_ARR=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $5}'))
LONGOPTS_ARR=($(grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $6}'))
IFS=$' '
fi

# silent install options
SHORT_OPTS=([0]="x" [1]="a" [2]="i" [3]="d")
SHORT_OPTS+=(${SHORTOPTS_ARR[@]})
LONG_OPTS=([0]="express" [1]="autostart" [2]="install" [3]="delete")
LONG_OPTS+=(${LONGOPTS_ARR[@]})
SHORT_DEL="false"
SHORT_INSTALL="false"
MOD_CM=""
OPT_FALSE=0

FIRST_SCREEN=0
CLEAR_CONTINUE="no"

UPGRADE=0
DOWNGRADE=0
MODIFY=0
FEATURES_POPULATED=0

ARCH="x86_64"
ISM_INI_FILE="/opt/dell/srvadmin/iSM/etc/ini/dcismdy64.ini"
SERVICES_SCRIPT="/etc/init.d/dcismeng"
SELECT_ALL="false"
AUTO_START="false"
EXPRESS="false"

OS2IDRAC_INI_FILE="/opt/dell/srvadmin/iSM/etc/ini/dcos2idrac.ini"
OS2IDRAC_PORT_NUM=0
PORT_ARG_STRING="port"
# OS2IDRAC feature index in DCISM_FEATURES_ENABLED_ARRAY

# OS2IDRAC feature specified in silent install
OS2IDRAC_ENABLED="false"

OS2IDRAC_SHORT_OPT="${SHORTOPTS_ARR[${OS2IDRAC_INDEX}]}"
OS2IDRAC_LONG_OPT="${LONGOPTS_ARR[${OS2IDRAC_INDEX}]}"

LCLOG_INDEX=1

SNMPTRAP_SCRIPT="/opt/dell/srvadmin/iSM/bin/Enable-iDRACSNMPTrap.sh"
IBIA_SCRIPT="/opt/dell/srvadmin/iSM/bin/Enable-iDRACAccessHostRoute"

TEMP_INI_FILE="/opt/dell/srvadmin/iSM/tmpdcism.ini"
trap 'rm -rf "$TEMP_INI_FILE" > /dev/null 2>&1'   EXIT ERR

ISMMUTLOGGER="/opt/dell/srvadmin/iSM/lib64/dcism/ismmutlogger"
MUT_LOG_FILE="/tmp/.dcismmutlogger"

###############################################################################
# Function : SetErrorAndInterrupt
#
#   The "tee" command used to write log, continues execution after
#   the "tee" when any part of the utility exits. Additionally, global
#   variables do not seem to be updated when execution resumes. So, all
#   exit errors are mapped to the signal HUP. kill works very quickly
#   AFTER exit is called, so to allow user messages to output, sleep
#   was added.
###############################################################################
function SetErrorAndInterrupt
{
    FF_EXIT=$1
    sleep 1
    exit $FF_EXIT
    kill -HUP $$
}

###############################################################################
# Function : Usage
#
## Display the usage messages
###############################################################################
function Usage {
cat <<EOF
Usage: ${0} [OPTION]...
iDRAC Service Module Install Utility. This Utility will run in the interactive
mode if no options are given and runs silently if one or more options are given

Options:

[-h|--help]     			Displays this help
[-i|--install]  			Installs and enables the selected features.
[-x|--express]  			Installs and enables all available features.
                			Any other options passed will be ignored.
[-d|--delete]   			Uninstall the iSM component.
[-a|--autostart]			Start the installed service after the component has
                			been installed.
EOF
for (( idx=0 ; idx<${FEATURE_COUNT}; idx++ ));
do
	if [[ idx -eq `expr $IBIA_INDEX ` ]]; then
		continue
	fi
	if [[ idx -eq $OS2IDRAC_INDEX ]]; then
		echo -e "[-${SHORTOPTS_ARR[$idx]}|--${LONGOPTS_ARR[$idx]}] [--${PORT_ARG_STRING}=<1024-65535>]\tEnables the ${DCISM_FEATURE_ARRAY[$idx]}."
	else
		echo -e "[-${SHORTOPTS_ARR[$idx]}|--${LONGOPTS_ARR[$idx]}]    \t\t\tEnables the ${DCISM_FEATURE_ARRAY[$idx]}."
	fi
done
if [ -n "$1" ] && [ "$1" = "Help" ]
then
        exit 0
fi
SetErrorAndInterrupt $ERROR
}

#check whether rpm/debian is installed.
function CheckPackage()
{
   CheckOSType
   if [ $? -eq 0 ]; then
		if rpm -q dcism &> /dev/null; then
	     	return 0
		fi
   else
		if [ $(dpkg-query -W -f='${Status}' dcism 2>/dev/null | grep -c "ok installed") -eq 1 ]; then
           return 0
        fi
   fi
   return 1
}

###############################################################################
# Function : ShowLicense
# Function will show license
#
###############################################################################
function ShowLicense()
{
   CheckPackage
   if [ $? -eq 1 ]
   then
       if [ -f "$LICENSEFILEPATH" ]
       then
           more "$LICENSEFILEPATH"
           echo ""
           echo -n "Do you agree to the above license terms? ('y' for yes | 'Enter' to exit): "
           read ANSWER
           answer=`echo "${ANSWER}" | sed 's#^[[:space:]]*##; s#[[:space:]]*$##'`
           if echo "${answer}" | grep -qi "^y$"
           then
               clear
           else
               exit 0
           fi
       fi
   fi
}
# check for help
    echo "${*}" | egrep "^.*--help.*$" >/dev/null 2>&1
    if [ $? == 0 ]; then
      Usage Help
    fi

    echo "${*}" | egrep "^.*-h.*$" >/dev/null 2>&1
    if [ $? == 0 ]; then
      Usage Help
    fi

# ensure sbin utilities are available in path, so that su will also work
export PATH=/usr/kerberos/sbin:/usr/local/sbin:/sbin:/usr/sbin:$PATH

# check for root privileges
if [ ${UID} != 0 ]; then
    echo "This utility requires root privileges"
    SetErrorAndInterrupt $UPDATE_PREREQ_NA
fi



###############################################
## Prompt
###############################################

function Prompt {
  MSG="${1}"

  # prompt and get response
  echo -n "${MSG}" 1>&2
  read RESP

  # remove leading/trailing spaces
  echo "${RESP}" | sed 's#^[[:space:]]*##; s#[[:space:]]*$##'
}

###############################################
#Is14GServer
#function to check whether the server is 14G.
###############################################
Is14GServer()
{
    if [ -n "${OM_SYSTEM_ID}" ]
    then
       SYSID_HEX="0x${OM_SYSTEM_ID}"
    else
        SYSID_STR=`dmidecode -t 208 | tail -3 | sed '2q;d'`
        SYSID_STR=`echo ${SYSID_STR:28:3}${SYSID_STR:25:3}`
        SYSID_HEX=`echo 0x${SYSID_STR//[[:blank:]]/}`
    fi

    SYSID_DEC=`printf "%d"  $SYSID_HEX`

    GBL_MIN_SYSID=`printf "%d" 0x04CE` # 12G min sysid
    if [ $SYSID_DEC -ge $GBL_MIN_SYSID ]; then
        return $TRUE
    else
        return $FALSE
    fi
}

###############################################################################
##
## Function:    GetOSType
##
## Decription:  Determines the operating system type.
##
## Returns:     0 = No error
##
## Return Vars: GBL_OS_TYPE=[GBL_OS_TYPE_ERROR|
##                           GBL_OS_TYPE_UKNOWN|
##                           GBL_OS_TYPE_RHEL5|
##                           GBL_OS_TYPE_SLES10|
##                           GBL_OS_TYPE_SLES11|
##                           GBL_OS_TYPE_SLES12|
##                           GBL_OS_TYPE_ESX40|
##                           GBL_OS_TYPE_ESX41]                ]
##                           GBL_OS_TYPE_RHEL6|
##              GBL_OS_TYPE_STRING=[RHEL5|SLES10|SLES11|SLES12|ESX40|ESX41||RHEL6|UNKNOWN]
##
###############################################################################

GetOSType()
{
    # Set default values for return variables.
    GBL_OS_TYPE=${GBL_OS_TYPE_UKNOWN}
    GBL_OS_TYPE_STRING="UKNOWN"

    Is14GServer
	check_server_status=$?
    # check if operating system is RHEL6.
    if [ -f /etc/redhat-release ] && [ `grep -Eci "Santiago|CentOs.* 6\..*" /etc/redhat-release` -gt 0 ]; then
        GBL_OS_TYPE=${GBL_OS_TYPE_RHEL6}
        GBL_OS_TYPE_STRING="RHEL6"
        PATH_TO_RPMS_SUFFIX=RHEL6
    elif [ -f /etc/redhat-release ] && [ `grep -Eci "Maipo|CentOs.* 7\..*" /etc/redhat-release` -gt 0 ]; then
        GBL_OS_TYPE=${GBL_OS_TYPE_RHEL7}
        GBL_OS_TYPE_STRING="RHEL7"
        PATH_TO_RPMS_SUFFIX=RHEL7
    # Else check if operating system is SLES.
    elif [ -f /etc/SuSE-release ]; then
        LOC_VERSION=`cat /etc/SuSE-release | grep "VERSION" | sed  -e 's#[^0-9]##g'`

        if [ $check_server_status -eq 1 ]; then
                # Check if operating system is SLES10.
                if [ "${LOC_VERSION}" = "10" ]; then
                        GBL_OS_TYPE=${GBL_OS_TYPE_SLES10}
                        GBL_OS_TYPE_STRING="SLES10"
                        PATH_TO_RPMS_SUFFIX=SLES10
				fi
        # Check if operating system is SLES11.
        #elif [ "${LOC_VERSION}" = "11" ]; then
        #        GBL_OS_TYPE=${GBL_OS_TYPE_SLES11}
        #       GBL_OS_TYPE_STRING="SLES11"
        #       PATH_TO_RPMS_SUFFIX=SLES11
		# else operating system is SLES12.
        elif [ "${LOC_VERSION}" = "12" ]; then
                GBL_OS_TYPE=${GBL_OS_TYPE_SLES12}
                GBL_OS_TYPE_STRING="SLES12"
                PATH_TO_RPMS_SUFFIX=SLES12
        fi
	elif [ -f /etc/os-release ]; then
		# check if operating system is UBUNTU OR SLES15		
		. /etc/os-release
		OS=$NAME
		VER=`echo $VERSION | cut -d"." -f1`
        #check for Ubuntu 16.
		#if [ "$OS" == "Ubuntu" ] && [ "$VER" == "16" ]; then
		#		GBL_OS_TYPE=${GBL_OS_TYPE_UBUNTU16}
		#		GBL_OS_TYPE_STRING="UBUNTU16"
		#		PATH_TO_RPMS_SUFFIX=UBUNTU16
		#fi
		#check for Ubuntu18.
		if [ "$OS" == "Ubuntu" ] && [ "$VER" == "20" ]; then
				GBL_OS_TYPE=${GBL_OS_TYPE_UBUNTU18}
				GBL_OS_TYPE_STRING="UBUNTU18"
				PATH_TO_RPMS_SUFFIX=UBUNTU18
		fi
		#check for SLES15
        if [ "$OS" == "SLES" ] && [ "$VER" == "15" ]; then
				GBL_OS_TYPE=${GBL_OS_TYPE_SLES15}
				GBL_OS_TYPE_STRING="SLES15"
				PATH_TO_RPMS_SUFFIX=SLES15
		fi		
    fi

    return 0
}

#check OS type whether ubuntu or not
function CheckOSType()
{
	if [ "$GBL_OS_TYPE_STRING" == "UBUNTU16" ] || [ "$GBL_OS_TYPE_STRING" == "UBUNTU18" ]; then
		return 1
	else
		return 0
	fi
}

######################## INI FUNCTIONS SECTION START #################
function ChangeINIKeyValue
{
	INI_FILENAME=$1
	SECTION=$2
	KEY=$3
	VALUE=$4

	FOUND_SECTION=1
	FOUND_KEY=1

	#do not execute without proper parameter count
	if [ ! $# -eq 4 ]
	then
		echo "Incorrect number of parameters"
		return 1
	fi

	#exit if ini file not present
	if [ ! -f "$INI_FILENAME" ]
	then
		return 1
	fi


	#read file line by line until we hit the required section
	#and the required key. perform the job and break

	while read LINE
	do
	if [ "$FOUND_SECTION" == 0 ] && [ "$FOUND_KEY" == 0 ]
		then
		echo "$LINE" >> "$TEMP_INI_FILE"
		continue
	fi

	#check if a section is found and set flag
	echo $LINE | grep -e "^\[${SECTION}\]$"> /dev/null 2>&1
	if [ $? == 0 ]
	then
		FOUND_SECTION=0
	fi

	#check if this line is the key required
	if [ "$FOUND_SECTION" == 0 ]
	then
		echo $LINE | grep -e "${KEY}" > /dev/null 2>&1
		if [ $? == 0 ]
		then
			LINE=`echo "${LINE}" | sed "s/${KEY}=.*/${KEY}=${VALUE}/g"`
			FOUND_KEY=0
		fi
	fi
	echo "$LINE" >> "$TEMP_INI_FILE"

	done < "$INI_FILENAME"

	cp -f "$TEMP_INI_FILE" "$INI_FILENAME"
	rm -f "$TEMP_INI_FILE"

	return 0
}
	
function GetFeaturesEnabledFromINI
{
	# just minus 1 to exclude option - All Features

	for (( idx=0 ; idx<${FEATURE_COUNT}; idx++ ));
	do
		DCISM_FEATURES_ENABLED_ARRAY[$idx]=`GetINIKeyValue "${ISM_INI_FILE}" "${DCISM_SECTIONS[$idx]}" "feature.enabled"`
		# BITS154141: omsa gui updates with uppercase letters for true/false which is not detected. So, changing the code to be case insensitive.
		#if [ "${DCISM_FEATURES_ENABLED_ARRAY[$idx]}" != "true" ]; then
		echo "${DCISM_FEATURES_ENABLED_ARRAY[$idx]}" | grep -i "true" > /dev/null 2>&1
		if [ $? -eq 0 ]; then
			DCISM_FEATURES_ENABLED_ARRAY[$idx]="true"
		else
			DCISM_FEATURES_ENABLED_ARRAY[$idx]="false"
		fi
	done
	FEATURES_POPULATED=1
}

function GetINIKeyValue
{
        INI_FILENAME=$1
        SECTION=$2
        KEY=$3
        VALUE=""

        FOUND_SECTION=1
        FOUND_KEY=1

        #do not execute without proper parameter count
        if [ ! $# -eq 3 ]
        then
			echo "Incorrect number of parameters"
			SetErrorAndInterrupt $ERROR
        fi

        #exit if ini file not present
        if [ ! -f $INI_FILENAME ]
        then
			SetErrorAndInterrupt $ERROR
        fi

        #read file line by line until we hit the required section
        #and the required key. perform the job and break

        while read LINE
        do
        if [ "$FOUND_SECTION" == 0 ] && [ "$FOUND_KEY" == 0 ]
		then
			break
        fi

        #check if a section is found and set flag
        echo $LINE | grep -e "^\[${SECTION}\]$"> /dev/null 2>&1
        if [ $? == 0 ]
		then
			FOUND_SECTION=0
		fi

        #check if this line is the key required
        if [ "$FOUND_SECTION" == 0 ]
        then
			echo $LINE | grep -e "${KEY}" > /dev/null 2>&1
			if [ $? == 0 ]
			then
				VALUE=`echo "${LINE}" | awk -F= '{print$2}'`
				FOUND_KEY=0
				echo $VALUE
				return 0
			fi
        fi
        done < $INI_FILENAME
        #return ""
}

#check package version during upgrade, modify
function PackageVersionVerify()
{
	PKG_VER=$1
	PKG_VER_TO_INSTALL=$2
	if [ ! -z $PKG_VER_TO_INSTALL ]; then
		if [ "$PKG_VER_TO_INSTALL" == "$PKG_VER" ]; then
			FIRST_SCREEN=2
			MODIFY=1
		elif [ "$PKG_VER_TO_INSTALL" \> "$PKG_VER" ]; then
			# upgrade
			FIRST_SCREEN=1
			UPGRADE=1
		elif [ "$PKG_VER_TO_INSTALL" \< "$PKG_VER" ]; then
			#downgrade -- do not support
			DOWNGRADE=1
			#exit here for silent install
			if [ ! -z "${MOD_CM}" ]
			then
				exit $UPDATE_FAILED_NEWER_VER_AVAILABLE
			fi	
		fi
	else
		# giving random number as 0=install 1=upgrade 2=uninstall (from webpack perspective) 
		# using 3 as script is executed within sbin dir or rpm/debian file not found.
		FIRST_SCREEN=3 
		SCRIPT_SOURCE="sbin"
	fi
}
######################## INI FUNCTIONS SECTION END #################

function CheckiSMInstalled
{
	PKG_NAMES=""
	PKG_NAME=""	
	CheckOSType
	if [ $? -eq 0 ]; then	
		PKG_NAMES=`rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH} %{VENDOR}\n' dcism | grep 'Dell Inc\.' 2>/dev/null` 
		PKG_NAME=`echo $PKG_NAMES | cut -d " " -f 1`
		if [ ! -z $PKG_NAME ]; then
			PKG_VER=`rpm -q $PKG_NAME --qf "%{version}"|sed "s/\.//g"`   
			PKG_VER_TO_INSTALL=`rpm -qp "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" --qf "%{version}" 2>/dev/null |sed "s/\.//g"`
			PackageVersionVerify $PKG_VER $PKG_VER_TO_INSTALL
			return 0
		fi
	else	
		CheckPackage
		if [ $? -eq 0 ]; then	
			PKG_NAME=`dpkg -s dcism | grep Package | awk '{ print $2 }'`
			if [ ! -z $PKG_NAME ]; then
				PKG_VER=`dpkg -s dcism | grep Version | awk '{ print $2 }'`
				CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Version"
				PKG_VER_TO_INSTALL=`$CMD`						 
				PackageVersionVerify $PKG_VER $PKG_VER_TO_INSTALL
				return 0
			fi
		fi
	fi
	return 1
}

###############################################################################
#  Function : PrintGreetings
#
###############################################################################

function PrintGreetings {
  cat <<EOF

#################################################

  OpenManage || iDRAC Service Module

#################################################

EOF
}

function ShowInstallOptions
{
    if [ "$FIRST_SCREEN" == 2 ]
    then
  cat <<EOF
   The version of iDRAC Service Module that you are trying to install is already installed.
   Select from the available options below.

EOF
    fi
    if [ "$FIRST_SCREEN" == 3 ]
    then
      cat <<EOF
   The iDRAC Service Module is already installed.
   Select from the available options below.

EOF
    return 0
    fi

    if [ "$UPGRADE" == 1 ] ; then
    cat <<EOF
   A previous verion of IDRAC Service Module ($PKG_NAME) is already installed with following features enabled.
   Please add/remove features required for upgrade

EOF
    fi
    if [ "$DOWNGRADE" == 1 ]; then
      cat <<EOF
   A newer version of IDRAC Service Module ($PKG_NAME) is already installed. Quitting !.

EOF
      exit $UPDATE_FAILED_NEWER_VER_AVAILABLE
    fi
    echo ""
    echo "    Available feature options: "
    echo ""
    ENABLED_PATT="[ ]"
    #j is a 1 based index. This is the option number
    i=0
    j=1

    while [ $i -lt $OPTION_COUNT ]
    do
      if [ "${DCISM_FEATURES_ENABLED_ARRAY[$i]}" == "true" ]
      then
          ENABLED_PATT="[x]"
      else
          ENABLED_PATT="[ ]"
      fi
      if [ $j -eq `expr $IBIA_INDEX + 1` ]; then
            if [ "${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]}" == "true" -o "${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]}" == "true" -o "${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]}" == "true" ]; then
            echo "   [x] $j. ${DCISM_FEATURE_ARRAY[${i}]}"
        else
            echo "   [ ] $j. ${DCISM_FEATURE_ARRAY[${i}]}"
        fi
            i=`expr $i + 1`
            j=`expr $j + 1`
            ENABLED_PATT=`[ "${DCISM_FEATURES_ENABLED_ARRAY[${i}]}" == "true" ] && echo "[x]" || echo "[ ]"`
            echo -e "\t""   ${ENABLED_PATT} a. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`
            ENABLED_PATT=`[ "${DCISM_FEATURES_ENABLED_ARRAY[${i}]}" == "true" ] && echo "[x]" || echo "[ ]"`
            echo -e "\t""   ${ENABLED_PATT} b. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`            
            ENABLED_PATT=`[ "${DCISM_FEATURES_ENABLED_ARRAY[${i}]}" == "true" ] && echo "[x]" || echo "[ ]"`
            echo -e "\t""   ${ENABLED_PATT} c. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`            
      elif [ $j -eq `expr $IDRAC_HARD_RESET_INDEX - 2` ]; then
            echo "       $j. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`
            j=`expr $j + 1`
      elif [ $j -eq `expr $SUPPORT_ASSIST_INDEX - 2` ]; then
            echo "       $j. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`
            j=`expr $j + 1`
      elif [ $j -eq `expr $FULLPOWER_CYCLE_INDEX - 2` ]; then
            echo "       $j. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`
            j=`expr $j + 1`
      else
            echo "   ${ENABLED_PATT} $j. ${DCISM_FEATURE_ARRAY[${i}]}"
            i=`expr $i + 1`
            j=`expr $j + 1`
      fi
    done
    

    # commented lines below not to show triggerable features in install script.
    #echo -ne "\e[90m"
    #for sec in "${DCISM_TRIGGERABLE_FEATURE_ARRAY[@]}"
    #do
    #   echo -e "   [x] $j. ${sec}"
    #   j=`expr $j + 1`
    #done
    #echo -ne "\e[0m"


    echo ""
    echo ""
}

function ValidateUserSelection
{
    if [ $1 -gt 0 -a $1 -lt 9 ]; then
       return 0
        else
           return 1
        fi
}

function toggle_feature_choice
{
	#this is because user selection in a 1 based index
	let "index=$1 - 1"

	#if all option was earlier selected
	if [ $1 != $OPTION_COUNT ] && [ "$SELECT_ALL" == "true" ]
	then
			SELECT_ALL="false"
			for (( idx=0 ; idx<${OPTION_COUNT}; idx++ ));
			do
				if [ "${DCISM_FEATURE_ARRAY[$idx]}" == "$IDRAC_HARD_RESET_STR" ] || [ "${DCISM_FEATURE_ARRAY[$idx]}" == "$SUPPORT_ASSIST_STR" ] || [ "${DCISM_FEATURE_ARRAY[$idx]}" == "$FULLPOWER_CYCLE_STR" ]; then
					DCISM_FEATURES_ENABLED_ARRAY[$idx]="true"
				else
					DCISM_FEATURES_ENABLED_ARRAY[$idx]="false"
				fi
			done
	fi

	#regular flow if earlier selected, deselect now
	if [ "${DCISM_FEATURES_ENABLED_ARRAY[$index]}" == "true" ]
	then
			if [ "${DCISM_FEATURE_ARRAY[$index]}" == "$IDRAC_HARD_RESET_STR" ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$index]="true"
			elif [ "${DCISM_FEATURE_ARRAY[$index]}" == "$SUPPORT_ASSIST_STR" ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$index]="true"
			elif [ "${DCISM_FEATURE_ARRAY[$index]}" == "$FULLPOWER_CYCLE_STR" ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$index]="true"
		else
			DCISM_FEATURES_ENABLED_ARRAY[$index]="false"
		fi
	else
			DCISM_FEATURES_ENABLED_ARRAY[$index]="true"
	fi

	#if all option is now selected
	if [ "$1" == "`expr $OPTION_COUNT - 1`" ]
	then
		SELECT_ALL="true"
		value="true"

		#Note we are using $index as the index variable.
		if [ "${DCISM_FEATURES_ENABLED_ARRAY[$index]}" == "true" ]
		then
			value="true"
		else
			value="false"
		fi

		for (( idx=0 ; idx<${OPTION_COUNT}; idx++ ));
		do
			if [ "${DCISM_FEATURE_ARRAY[$idx]}" == "$IDRAC_HARD_RESET_STR" ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$idx]="true"
			elif [ "${DCISM_FEATURE_ARRAY[$idx]}" == "$SUPPORT_ASSIST_STR" ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$idx]="true"
			elif [ "${DCISM_FEATURE_ARRAY[$idx]}" == "$FULLPOWER_CYCLE_STR" ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$idx]="true"
			else
				DCISM_FEATURES_ENABLED_ARRAY[$idx]=$value
			fi
		done
	fi
}

###############################################################################
# Function : AddLongOpt
#
## Process long command line options
###############################################################################
function AddLongOpt {

  local i=0
  for ((i=0; i<$OPTION_COUNT;i++ ))
  do
        if [ "${1}" == "${LONGOPTS_ARR[$i]}" ]; then
                DCISM_FEATURES_ENABLED_ARRAY[$i]="true"
		FEATURE_OPT="true"
        fi
  done

  if [ "${1}" == "express" ]; then
        EXPRESS="true"
  elif [ "${1}" == "install" ]; then
        SHORT_INSTALL="true"
  elif [ "${1}" == "delete" ]; then
        SHORT_DEL="true"
  elif [ "${1}" == "autostart" ]; then
    AUTO_START="true"
  elif [ "${FEATURE_OPT}" != "true" ] && [ ${1} != "help" ] ; then
	echo "Invalid Option ${1}. Please see usage"
	Usage Help
  fi
}

###############################################################################
# Function : ShortOptionFalse 
#
#This will check if supplied options are one of the feature available in install.ini file. Then it will make all feature false and later code will make only user selected
#options true. if none of the feture is provided by user then enabled feature list will be taken from install.ini file.
###############################################################################
function ShortOptionFalse {
if [ -f $INSTALL_CONFIG ]; then
   local i=0
   TEST=`grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $5}' | tr -d '\n'`
   grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $5}' | tr -d '\n'| grep -E `echo ${1}| sed "s/[$TEST]/&\|/g"` >/dev/null 2>&1
   RET=$?

   if [ $RET == 0 ] && [ $OPT_FALSE == 0 ]; then
    for ((i=0; i<$OPTION_COUNT;i++ ))
    do
        DCISM_FEATURES_ENABLED_ARRAY[$i]="false"
	OPT_FALSE=1
    done
   fi
fi

}
###############################################################################
# Function : AddShortOpt
#
## Process short command line options
###############################################################################
function AddShortOpt {

   local i=0
   for SHORT_OPT in `echo "${1}" | sed "s/[a-zO]/& /g"`; do
    for ((i=0; i<$OPTION_COUNT;i++ ))
    do
        if [ "${SHORT_OPT}" == "${SHORTOPTS_ARR[$i]}" ]; then
            DCISM_FEATURES_ENABLED_ARRAY[$i]="true"
	    FEATURE_OPT="true"
        fi
    done   
    if [ "${SHORT_OPT}" == "x" ]; then
                EXPRESS="true"
    elif [ "${SHORT_OPT}" == "d" ]; then
                SHORT_DEL="true"
    elif [ "${SHORT_OPT}" == "i" ]; then
                SHORT_INSTALL="true"
    elif [ "${SHORT_OPT}" == "a" ]; then
                AUTO_START="true"
    elif [ "${FEATURE_OPT}" != "true" ] && [ ${1} != "h" ]; then
		echo "Invalid Option ${1}. Please see usage"
		Usage Help
    fi

   
  done
}

###############################################################################
# Function : LongOptionFalse 
#
#This will check if supplied options are one of the feature available in install.ini file. Then it will make all feature false and later code will make only user selected
#options true. if none of the feture is provided by user then enabled feature list will be taken from install.ini file.
###############################################################################
function LongOptionFalse {
if [ -f $INSTALL_CONFIG ]; then
    local i=0
    grep -vE "^#|triggered" "$INSTALL_CONFIG" | awk -F"|" '{print $6}' | tr  '\n' ' '|grep -E `echo "${1}" | tr -d '-'|sed -e "s/ /|/g"` >/dev/null 2>&1
    RET=$?
    if [ $RET == 0 ] && [ $OPT_FALSE == 0 ]; then
    for ((i=0; i<$OPTION_COUNT;i++ ))
       do
          if [ "${1}" != "${LONGOPTS_ARR[$i]}" ]; then
              DCISM_FEATURES_ENABLED_ARRAY[$i]="false"
	      OPT_FALSE=1
          fi
       done
    fi
fi
}

###############################################################################
# Function : ValidateOpts
#
## Validate command line options
###############################################################################
function ValidateOpts {
  if [ $# -gt 0 ]; then
    # invald characters
    #BY  added //,.,_,0-9,A-Z
    echo "${*}" | sed "s/ //g" | egrep "^[-/._a-z0-9O=//]+$" >/dev/null 2>&1
    if [ $? != 0 ]; then
      echo "Invalid Options, please see the usage below"
      echo ""
      Usage
    fi

    MOD_CM=$*
    local i=0
# replace  $* by $MOD_CM which does not contain --prefix <path>
for param in $MOD_CM; do
      # check for long option
      echo "${param}" | egrep "^--[a-zO2\-]+$" >/dev/null 2>&1
      if [ $? == 0 ]; then
        GOOD_LONG_OPT=1
        for (( i=0 ; i<${#LONG_OPTS[*]} ; i++ )); do
          if [ "${param}" == "--${LONG_OPTS[i]}" ]; then
            GOOD_LONG_OPT=0
            if [ "${LONG_OPTS[i]}" == "${OS2IDRAC_LONG_OPT}" ]; then
                OS2IDRAC_ENABLED="true"
            fi
	    LongOptionFalse "${MOD_CM}"
            AddLongOpt ${LONG_OPTS[i]}
            break
          fi
        done

        if [ ${GOOD_LONG_OPT} != 0 ]; then
          echo "Invalid Option ${param}, please see the usage below"
          Usage
        fi
      else
        # check for short option
        VALID_SHORT_OPTS=`echo "${SHORT_OPTS[*]}" | sed "s/ //g"`
        echo "${param}" | egrep "^-[${VALID_SHORT_OPTS}]+$" >/dev/null 2>&1
        if [ $? == 0 ]; then
          TEMP_OPT=`echo "${param}" | sed "s/-//"`
          echo "${OS2IDRAC_SHORT_OPT}" | egrep "[${TEMP_OPT}]" >/dev/null 2>&1
          if [ $? == 0 ]; then
          	OS2IDRAC_ENABLED="true"
          fi
	  ShortOptionFalse ${TEMP_OPT}
          AddShortOpt ${TEMP_OPT}
        else
		echo "${param}" | egrep "^--${PORT_ARG_STRING}=[0-9]+$" >/dev/null 2>&1
		if [ $? == 0 ]; then
			OS2IDRAC_PORT_NUM=`echo "${param}" | sed "s/--${PORT_ARG_STRING}=//g"`
			if ! ( [[ $OS2IDRAC_PORT_NUM =~ ^[0-9]+$ ]] && (( $OS2IDRAC_PORT_NUM > 1023 )) && (( $OS2IDRAC_PORT_NUM < 65536 )) ); then
				echo "Invalid Port number, please see the usage below"
				Usage
			fi
		else
			echo "Invalid Option ${param}, please see the usage below"
			Usage
		fi
        fi
      fi
done
  fi
}
###############################################################################
#
#  function CheckForMultipleSelection
#
#
#
###############################################################################

function CheckForMultipleSelection {
    # remove any space characters
    STRIPPED_INPUT=`echo "$1" | sed "s/ //g"`

    OPTPKGARRLEN=$OPTION_COUNT
    ARR_IDX=1
    # only process multiple selection less or eq to arr len
    while [ ! $ARR_IDX -gt $OPTPKGARRLEN ] && [ ! -z "$STRIPPED_INPUT" ];
    do
        INDEX=`expr index "$STRIPPED_INPUT" ","`
        LEN=`expr length $STRIPPED_INPUT`
        if [ $INDEX == 0 ];
        then
            ValidateUserSelection $STRIPPED_INPUT
            if [ $? == 0 ];
            then
                #UpdatePkgSlection
                                toggle_feature_choice $STRIPPED_INPUT
            fi
            break
        elif [ $INDEX -lt $LEN ] || [ $INDEX == $LEN ];
        then
            INDEX=`expr $INDEX - 1`
            NUM_INPUT=`expr substr "$STRIPPED_INPUT" 1 $INDEX`
            if [ ! -z "$NUM_INPUT" ];
            then
                ValidateUserSelection $NUM_INPUT
                if [ $? == 0 ];
                then
                    #UpdatePkgSlection
                                        toggle_feature_choice $NUM_INPUT
                fi
                INDEX=`expr $INDEX + 2`
                STRIPPED_INPUT=`expr substr "$STRIPPED_INPUT" $INDEX $LEN`
                ARR_IDX=`expr $ARR_IDX + 1`
            else
                break
            fi
        else
           break
        fi
    done
}

function TakeUsersInputOnOptions
{
    if [ $FIRST_SCREEN == 0 ]
    then
    cat <<EOF
  Enter the number to select/deselect a feature from the above list.
		( multiple feature selection should be comma separated)
		( to select sub-features, please use 4.a,4.b, etc.)
  Enter q to quit.

EOF
    elif [ $FIRST_SCREEN == 1 ]
    then
    cat <<EOF
  Enter the number to select/deselect a feature
        ( multiple feature selection should be comma separated)
		( to select sub-features, please use 4.a,4.b, etc.)
  Enter i to install the selected features.
  Enter q to quit.

EOF
   else
        #Handle modify, uninstall and upgrade here
   cat <<EOF

  Enter the number to select/deselect a feature
        ( multiple feature selection should be comma separated)
		( to select sub-features, please use 4.a,4.b, etc.)
  Enter d to uninstall the component.
  Enter q to quit.

EOF

    fi

    opt_pkg_index=`Prompt "  Enter : "`
    LIMIT=`expr $OPTION_COUNT % 10`
    # check if number
     if [ `echo $opt_pkg_index | egrep "^[1-9][0-$LIMIT]?$" ` ]; then
        ValidateUserSelection $opt_pkg_index
        if [ $? == 0 ]; then
            FIRST_SCREEN=1
            CLEAR_CONTINUE="yes"
            if [ $opt_pkg_index -eq `expr $IBIA_INDEX + 1` ]; then
				toggle_feature_choice $opt_pkg_index
                if [ "${DCISM_FEATURES_ENABLED_ARRAY[${IBIA_INDEX}]}" == "true" ]; then
                    if [ ${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]} == "false" ]; then
                        toggle_feature_choice `expr $SNMPTRAP_INDEX`
                    fi
                    if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]} == "false" ]; then
                        toggle_feature_choice `expr $SNMPTRAP_INDEX + 1`
                    fi
                    if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]} == "false" ]; then
                        toggle_feature_choice `expr $SNMPTRAP_INDEX + 2`
                    fi
                else
                    if [ ${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]} == "true" ]; then
                        toggle_feature_choice `expr $SNMPTRAP_INDEX`
                    fi
                    if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]} == "true" ]; then
                        toggle_feature_choice `expr $SNMPTRAP_INDEX + 1`
                    fi
                    if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]} == "true" ]; then
                        toggle_feature_choice `expr $SNMPTRAP_INDEX + 2`
                    fi
                fi
            elif [ $opt_pkg_index -eq `expr $ALLFEATURES_INDEX - 2 ` ]; then
                toggle_feature_choice $ALLFEATURES_INDEX
	    elif [ $opt_pkg_index -eq `expr $IDRAC_HARD_RESET_INDEX - 2` ] || [ $opt_pkg_index -eq `expr $SUPPORT_ASSIST_INDEX - 2` ] || [ $opt_pkg_index -eq `expr $FULLPOWER_CYCLE_INDEX - 2` ]; then
			CLEAR_CONTINUE="yes"
            else
                toggle_feature_choice $opt_pkg_index
            fi
			let "index=$opt_pkg_index - 1"
		else
            echo "Unknown option."
			echo "Press any key to continue..."
			read
			CLEAR_CONTINUE="yes"
        fi
     else
        opt_pkg_index=`echo "$opt_pkg_index" | tr 'a-z' 'A-Z'`
        if [ "$opt_pkg_index" == "Q" ]; then
            kill -EXIT $$
            sleep 1
            exit 2
        elif [ "$opt_pkg_index" == "D" ]; then
            #  UnInstallPackages
               CLEAR_CONTINUE="no"
                #"${SERVICES_SCRIPT}" stop
				#log to MUTlogger during uninstall
				setMUTlog 1
				CheckOSType
				if [ $? -eq 0 ]; then
                    rpm -e dcism 2>/tmp/ism.err
					if [ $? -ne 0 ]; then
						cat /tmp/ism.err
						echo "Failed to uninstall iSM rpm .. Exiting !!"
						exit $UNINSTALL_FAILED
					fi
				else
                    dpkg -P dcism 2>/tmp/ism.err >/dev/null
					if [ $? -ne 0 ]; then
						cat /tmp/ism.err
						echo "Failed to uninstall iSM debian .. Exiting !!"
						exit $UNINSTALL_FAILED
					fi
				fi
            ldconfig >> /dev/null 2>&1
			if [ -f /tmp/ism.err ]; then
				rm -f /tmp/ism.err
			fi
            exit 0
        elif [ "$opt_pkg_index" == "I" ]; then
            #  InstallPackages
                        CLEAR_CONTINUE="no"
					#check for install/upgrade for mutlogger
				if [ $UPGRADE -ne 1 ]; then
					setMUTlog 0 #install
				else
					setMUTlog 2 #upgrade
				fi
            if [ $MODIFY -ne 1 ]; then
				CheckOSType
				if [ $? -eq 0 ]; then
						rpm -Uvh "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" 2>/tmp/ism.err
						if [  $? -ne 0 ]; then
                    		cat /tmp/ism.err
                    		echo "Error installing iSM rpm... Exiting !!"
                    		exit $UPDATE_FAILED
						fi
				else
					CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Depends"
					dependencies_pkgs=`$CMD`
                    IFS=', ' read -r -a dpnd <<< "$dependencies_pkgs"
                    for pkg in "${dpnd[@]}"
                    do
						if [ $(dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
							echo "Dependency package $pkg is missing.."
							exit $UPDATE_FAILED
						fi
					done				
                	dpkg -i "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" 2>/tmp/ism.err >/dev/null
			       	if [  $? -ne 0 ]; then
                    		cat /tmp/ism.err
                    		echo "Error installing iSM debian... Exiting !!"
                    		exit $UPDATE_FAILED
                	fi
				fi
            fi
      else
            # check for multiple selection, comma separated
                for opt_index in $(echo $opt_pkg_index | sed "s/,/ /g")
                do              
                    IFS='.' read -ra sub_options <<< "$opt_index"  #check whether there is sub option like 4.a/4.b
					#this check is for toggle between sub options
                    if [ `echo $sub_options | egrep "^[1-9]+$" ` ]; then
						if [ $sub_options -eq `expr $IBIA_INDEX + 1` ]; then
								if [ `echo ${sub_options[1]} | egrep "^[1-$OS2IDRAC_INDEX]+$" ` ]; then
									echo "Unknown option."
									echo "Press any key to continue..."
									read
									CLEAR_CONTINUE="yes"
								fi
								CheckForMultipleSelection $sub_options
								if [ "${sub_options[1]}" == "A" ]; then
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]} == "true" -o ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]} == "true" ]; then
                            			opt_pkg_index=$sub_options
                            			let "opt_pkg_index=sub_options + 1"
										CheckForMultipleSelection $opt_pkg_index
									else
						       			opt_pkg_index=$sub_options                            
                            			CheckForMultipleSelection $opt_pkg_index
                            			let "opt_pkg_index=sub_options + 1"
										CheckForMultipleSelection $opt_pkg_index
									fi
								elif [ "${sub_options[1]}" == "B" ]; then
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]} == "true" -o ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]} == "true" ]; then
                            			opt_pkg_index=$sub_options
                            			let "opt_pkg_index=sub_options + 2"
										CheckForMultipleSelection $opt_pkg_index
									else
                            			opt_pkg_index=$sub_options
                            			CheckForMultipleSelection $opt_pkg_index
                            			let "opt_pkg_index=sub_options + 2"
										CheckForMultipleSelection $opt_pkg_index
									fi
								elif [ "${sub_options[1]}" == "C" ]; then
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]} == "true" -a ${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]} == "true" ]; then
										opt_pkg_index=$sub_options
                            			let "opt_pkg_index=sub_options + 3"
										toggle_feature_choice $opt_pkg_index
									else
                            			opt_pkg_index=$sub_options
                            			CheckForMultipleSelection $opt_pkg_index
                            			let "opt_pkg_index=sub_options + 3"
										toggle_feature_choice $opt_pkg_index
									fi
								fi
							    if [ -z "${sub_options[1]}" -a  "${DCISM_FEATURES_ENABLED_ARRAY[${IBIA_INDEX}]}" == "true" ]; then
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]} == "false" ]; then
										toggle_feature_choice `expr $SNMPTRAP_INDEX`
									fi
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]} == "false" ]; then
										toggle_feature_choice `expr $SNMPTRAP_INDEX + 1`
									fi
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]} == "false" ]; then
										toggle_feature_choice `expr $SNMPTRAP_INDEX + 2`
									fi
								elif [ -z "${sub_options[1]}" -a  "${DCISM_FEATURES_ENABLED_ARRAY[${IBIA_INDEX}]}" == "false" ]; then
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${OS2IDRAC_INDEX}]} == "true" ]; then
										toggle_feature_choice `expr $SNMPTRAP_INDEX`
									fi
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPTRAP_INDEX}]} == "true" ]; then
										toggle_feature_choice `expr $SNMPTRAP_INDEX + 1`
									fi
									if [ ${DCISM_FEATURES_ENABLED_ARRAY[${SNMPGET_INDEX}]} == "true" ]; then
										toggle_feature_choice `expr $SNMPTRAP_INDEX + 2`
									fi
								fi
								FIRST_SCREEN=1
								CLEAR_CONTINUE="yes"
                    	else
			               	opt_pkg_index=$opt_index
							#skip if the options are feature advertisements like iDRAC Hard Reset, Support Assist etc.., in case of multiple option selection.
							if [ $opt_pkg_index -eq `expr $IDRAC_HARD_RESET_INDEX - 2` ] || [ $opt_pkg_index -eq `expr $SUPPORT_ASSIST_INDEX - 2` ] || [ $opt_pkg_index -eq `expr $FULLPOWER_CYCLE_INDEX - 2` ]; then
                                CLEAR_CONTINUE="yes"
                            else
								CheckForMultipleSelection $opt_pkg_index
								if [ $? != 0 ]; then
									FIRST_SCREEN=0
								else
									FIRST_SCREEN=1
									CLEAR_CONTINUE="yes"
								fi
							fi
                    	fi                        
                    else
                        echo "Unknown option."
                        echo "Press any key to continue..."
						read
						CLEAR_CONTINUE="yes"
                    fi
			done
		fi
	fi

    if [ $CLEAR_CONTINUE == "yes" ]; then
        # clear the screen and start over
        clear
        PrintGreetings
        ShowInstallOptions
        TakeUsersInputOnOptions
    fi

        return 0
}

###############################################################################
# Function : GetPathToScript
#
# extracts the path to the script, this path will be used to locate
# the rpms repository on the CD or on the system
#
###############################################################################

function GetPathToScript ()
{
    # $1 is the path to the script, inluding the script name
    REPLACE_ANY_SPACES=`echo "$1" | sed "s/ /\\\ /"`
    PATH_TO_SCRIPT=`dirname "$REPLACE_ANY_SPACES"`
    SCRIPTNAME=`basename $1`

    CURDIR=`pwd | sed "s/ /\\\ /"`
    cd "$PATH_TO_SCRIPT"
    SYSIDFILEPATH="`pwd | sed "s/ /\\\ /"`"

    LICENSEFILEPATH="$SYSIDFILEPATH/$LICENSEFILE"

    cd "$CURDIR"
}

function PerformPrereqChecks
{
   . "$SYSIDFILEPATH/prereq/CheckSystemType.sh" "$SYSIDFILEPATH"

    IsThisSupportedGeneration
    # Check whether a valid system ID is available and is a supported DELL server
    if [ $? != 0 ]; then
           echo "Unsupported system"
           exit $UPDATE_PREREQ_NA
    fi
        ARCH=`uname -i`

    # operating system check
    GetOSType
    if [ "${GBL_OS_TYPE}" = "${GBL_OS_TYPE_UKNOWN}" ] || [ "${GBL_OS_TYPE}" = "${GBL_OS_TYPE_ERROR}" ] || [ $ARCH != "x86_64" ]; then
        # Operating system type is unknown, or an error occurred trying to
        # determine the operating system type. Exit with Error 2
   cat <<EOF
     Unrecognized Operating System or Architecture. This script cannot
     continue with the installation. Select packages from the OS folder in
     the media that closely matches this Operating System to continue
     with the manual install.
EOF
        exit $UPDATE_PREREQ_NA
    fi

        #check whether iSM is already installed
        CheckiSMInstalled
}


function PerformPostInstall
{
#Replace new ini file since config files are not replaced during package upgrade.
if [ $UPGRADE == 1 ]; then
	if [ -f ${ISM_INI_FILE}.rpmnew ]; then
		mv -f ${ISM_INI_FILE}.rpmnew ${ISM_INI_FILE} 2>/dev/null
	fi
	if [ -f ${OS2IDRAC_INI_FILE}.rpmnew ]; then
		mv -f ${OS2IDRAC_INI_FILE}.rpmnew ${OS2IDRAC_INI_FILE} 2>/dev/null
	fi
fi

# stop service if modify
if [ $MODIFY -eq 1 ]; then
	StartStopService stop
fi


#check flag if rpm install was successful
#check whether is installed or not
CheckiSMInstalled
if [ $? -eq 0 ]
then
	#always set this parameter to false
	ChangeINIKeyValue "${ISM_INI_FILE}" "Agent Manager" "InstallerConsumed.enabled" "false"
	if [ ! -z "${MOD_CM}" ]; then
		if [ $PREDEFINE_OPTION -eq 1 -a $MODIFY -eq 1 ]; then
			GetFeaturesEnabledFromINI
		elif [ $PREDEFINE_OPTION -eq 1 ]; then
			GetFeaturesEnabledFromINI
		fi
	fi
	if [ "${DCISM_FEATURES_ENABLED_ARRAY[$SNMPTRAP_INDEX]}" == "true" ]; then
		${SNMPTRAP_SCRIPT} enable >> /dev/null 2>&1
	else
		${SNMPTRAP_SCRIPT} disable >> /dev/null 2>&1
	fi

	#using a new variable because OPTION_COUNT is 1 count extra for all features
	OPTIONS=7
	index=0
	while [ $index -lt $OPTIONS ]
	do
	if [ $EXPRESS == "true" ] && [ $index -ne $OS2IDRAC_INDEX ]; then
		DCISM_FEATURES_ENABLED_ARRAY[$index]=true
	fi

	if [ $index -ne $OS2IDRAC_INDEX ]; then
		ChangeINIKeyValue "${ISM_INI_FILE}" "${DCISM_SECTIONS[$index]}" "feature.enabled" "${DCISM_FEATURES_ENABLED_ARRAY[$index]}"
	fi
	index=`expr $index + 1`
	done

	#if this is a silent install
	if [ ! -z "${MOD_CM}" ]
	then
		if [ "$OS2IDRAC_ENABLED" == "true" ]; then
			ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" "$OS2IDRAC_PORT_NUM"
		fi
		if [ $AUTO_START == "true" ]
		then
		ldconfig >> /dev/null 2>&1
		#"${SERVICES_SCRIPT}" start
		StartStopService start

		fi
	else
        # port input for iDRAC access via Host OS
        if [ "${DCISM_FEATURES_ENABLED_ARRAY[$OS2IDRAC_INDEX]}" == "true" ]; then
            while true
            do
				LISTENPORT=`grep '^listen_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
                echo ""
                read -e -i "$LISTENPORT" -p "Enter a valid port number for iDRAC access via Host OS or Enter to take default port number: " PORT_NUM

                    if [[ $PORT_NUM =~ ^[0-9]+$ ]] && (( $PORT_NUM > 1023 )) && (( $PORT_NUM < 65536 ))
                    then
                        echo ""
                        ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" "$PORT_NUM"
                        break
                    else
                        LISTENPORT=`grep '^listen_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
                        IANAPORT=`grep '^iana_default_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
                        if [ ! -z $LISTENPORT ] && [ -z $PORT_NUM ]
                        then
                            echo ""
                            break
                        elif [ ! -z $IANAPORT ] && [ -z $PORT_NUM ]
                        then
                            if [[ $IANAPORT =~ ^[0-9]+$ ]] && (( $IANAPORT > 1023 )) && (( $IANAPORT < 65536 ))
                            then
                                echo ""
                                ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" "$IANAPORT"
                                break
                            fi
                        fi
                        PORT_NUM=""
                    fi
                    echo "Port number is invalid or default port number is not configured"
            done
	else
            # The below code is added to disable IBIA feature when the feature is de-selected during Upgrade
            ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "enabled" ""
            ChangeINIKeyValue "${OS2IDRAC_INI_FILE}" "OS2iDRAC" "listen_port" ""
        fi

		cat <<EOF

Do you want the services started?



EOF
		sa_start=`Prompt "   Press ('y' for yes | 'Enter' to exit): "`

		# now start if 'yes'
		if echo "${sa_start}" | grep -qi "^y$" ; then

			ldconfig >> /dev/null 2>&1
			#"${SERVICES_SCRIPT}" start
			StartStopService start
			echo ""
		fi
	fi
fi
}

function UpdateOS2IDRACPortFromINIFile {

    if [ "${OS2IDRAC_ENABLED}" == "true" ] && [ $OS2IDRAC_PORT_NUM -eq 0 ]
    then
            LISTENPORT=`grep '^listen_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
            IANAPORT=`grep '^iana_default_port' "${OS2IDRAC_INI_FILE}" | cut -d "=" -f 2`
        if [ -z $LISTENPORT ]; then
            OS2IDRAC_PORT_NUM=$IANAPORT
        else
            OS2IDRAC_PORT_NUM=$LISTENPORT
        fi
    fi
}

#UpdateOS2IDRACPortFromINIFile function is called two places at modify and upgrade case.
function InstallPackageSilent
{
    # if port is specified make sure OS2IDRAC is specified too
    if [ "${OS2IDRAC_ENABLED}" == "false" ] && [ $OS2IDRAC_PORT_NUM -ne 0 ]
    then
        echo "Invalid Options, please see the usage below"
        Usage
    fi

    CheckiSMInstalled
    if [ $? != 0 ] || [ $UPGRADE == 1 ]; then
	CheckOSType
        if [ $? -eq 0 ]; then
        	rpm -Uvh "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" 2>/tmp/ism.err
            if [  $? -ne 0 ]; then
                cat /tmp/ism.err
                echo "Error installing iSM rpm... Exiting !!"
                exit $UPDATE_FAILED
            fi
        else
			CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Depends"
			dependencies_pkgs=`$CMD`
			IFS=', ' read -r -a dpnd <<< "$dependencies_pkgs"
			for pkg in "${dpnd[@]}"
			do
				if [ $(dpkg-query -W -f='${Status}' $pkg 2>/dev/null | grep -c "ok installed") -eq 0 ]; then
					echo "Dependency package $pkg is missing.."
					exit $UPDATE_FAILED
				fi
			done
            dpkg -i "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" 2>/tmp/ism.err
            if [  $? -ne 0 ]; then
                 cat /tmp/ism.err
                echo "Error installing iSM debian... Exiting !!"
                exit $UPDATE_FAILED
            fi
		fi
        UpdateOS2IDRACPortFromINIFile
        PerformPostInstall
    elif [ $MODIFY -eq 1 ]; then
        UpdateOS2IDRACPortFromINIFile
        PerformPostInstall
    else
        echo "Service Module already installed"
        exit $UPDATE_NOT_REQD
    fi

}

function StartStopService 
{
operation=$1
if [ $GBL_OS_TYPE_STRING = "RHEL7" ] || [ $GBL_OS_TYPE_STRING = "SLES12" ] || [ $GBL_OS_TYPE_STRING = "SLES15" ] || [ $GBL_OS_TYPE_STRING = "UBUNTU16" ] || [ $GBL_OS_TYPE_STRING = "UBUNTU18" ]; then
	systemctl $operation dcismeng.service >> /dev/null 2>&1
else
	${SERVICES_SCRIPT} $operation >> /dev/null 2>&1
fi
result=$?
# stop does not require error check
if [ "$operation" != "stop" ] && [ $result -ne 0 ]; then
	echo "Failed to $operation the iSM service .. Exiting !!"
	exit $SERVICE_FAILED_TO_START
fi
if [ "$operation" == "start" ]; then
        CheckUSBNIC
fi
}

function UninstallPackageSilent
{
#"${SERVICES_SCRIPT}" stop
	#log to MUT logger during silent uninstall
	setMUTlog 1
	CheckOSType
    if [ $? -eq 0 ]; then
        rpm -e dcism 2>/tmp/ism.err
        if [ $? -ne 0 ]; then
            cat /tmp/ism.err
            echo "Failed to uninstall iSM rpm .. Exiting !!"
            exit $UNINSTALL_FAILED
        fi
    else
        dpkg -P dcism 2>/tmp/ism.err >/dev/null
        if [ $? -ne 0 ]; then
            cat /tmp/ism.err
            echo "Failed to uninstall iSM debian .. Exiting !!"
            exit $UNINSTALL_FAILED
        fi
    fi
	ldconfig >> /dev/null 2>&1
	if [ -f /tmp/ism.err ]; then
		rm -f /tmp/ism.err
	fi
}

#Check USB NIC communication status
function CheckUSBNIC
{
	COUNTER=0
	ConnectStatus=0
	newlineCounter=0
       	echo "  Checking for iSM communication with iDRAC..."	
       	echo -ne "    Waiting..."	
       	echo -ne "			"	
        while [  $COUNTER -lt 12 ]; do
             /opt/dell/srvadmin/iSM/bin/dchosmicli 0 3 > /dev/null
	     if [ $? -eq 0 ];then
		let ConnectStatus=ConnectStatus+1
	     	echo -ne " [100%]"
		break
	     fi
	     let newlineCounter=newlineCounter+1
             let COUNTER=COUNTER+1
	     if [ $newlineCounter -gt 6 ]; then
		newlineCounter=0
		echo ""
       		echo -ne "			        "	
	     fi
	     echo -ne "#####"
             pid=`pidof dsm_ism_srvmgrd`
	     if [  -z "$pid" ]; then
		break
	     fi		 
	     sleep 10 
        done
	echo ""
	if [ $ConnectStatus -eq 0 ];then
	
            echo "  iSM is unable to communicate with iDRAC. Please refer the FAQs section in Install Guide."
	else	
            echo "  iSM communication with iDRAC is established successfully."
	fi
} #CheckUSBNIC

#function to get iSM version to be installed.
function getVersion
{
	CheckOSType
	if [ $? -eq 0 ]; then
		ISM_VERSION=`rpm -qp "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/dcism*.rpm" --qf "%{version}"`        
    else
        CMD="dpkg-deb -f "$SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/`ls $SYSIDFILEPATH/$GBL_OS_TYPE_STRING/$ARCH/ | grep deb`" Version"
		ISM_VERSION=`$CMD` 
    fi
}

#function to log in mutlogger, gets arguements a 0-Install,1-Uninstall,2-Upgrade
function setMUTlog
{
	opt=() # array to collect enabled features in long options formats
    for i in "${!DCISM_FEATURE_ARRAY[@]}"; do
        if [ $i -ne $ALLFEATURES_INDEX -a $i -ne $IBIA_INDEX ]; then
			echo "${DCISM_FEATURES_ENABLED_ARRAY[$i]}" | grep -i "true" > /dev/null 2>&1
			if [ $? -eq 0 ]; then
				if [ $i -eq $OS2IDRAC_INDEX ]; then
					opt+=("OS2iDRAC")
				elif [ $i -eq $IDRAC_HARD_RESET_INDEX ]; then
					opt+=("iDRACHardReset")
				else
					opt+=("${LONGOPTS_ARR[$i]}")
				fi
			fi
        fi
    done
    enbld_opts=$(IFS=,;echo "${opt[*]}")
	getVersion
    if [ $1 -eq 0 ]; then #for install
        echo "Install$ISM_VERSION os=$GBL_OS_TYPE_STRING.install:$enbld_opts:remove:null,installmethod=webpack" > $MUT_LOG_FILE
    elif [ $1 -eq 1 ]; then #for uninstall
        echo "Remove$ISM_VERSION os=$GBL_OS_TYPE_STRING.install:null:remove:$enbld_opts,installmethod=webpack" > $MUT_LOG_FILE
    else
        echo "Upgrade$ISM_VERSION os=$GBL_OS_TYPE_STRING.install:$enbld_opts,installmethod=webpack" > $MUT_LOG_FILE #for upgrade
    fi
}


###############################################################################
# Function : Main
#
# This is the starting point for the script, this
# function invokes other functions in the required
# order
###############################################################################
function Main
{
    GetOSType
    CheckiSMInstalled

    if [ $? != 0 ]
    then
       PerformPrereqChecks
    fi

    #Show License if there are no options passed
    if [ -z "$1" ]
    then
       ShowLicense
    fi

	if [ $FEATURES_POPULATED != 1 ]; then
		if [ $UPGRADE == 1 ] || [ $MODIFY == 1 ]; then
			GetFeaturesEnabledFromINI
			# SNMP TRAPs check
			${SNMPTRAP_SCRIPT} status >> /dev/null 2>&1
			if [ $? == 0 ]; then
				DCISM_FEATURES_ENABLED_ARRAY[$SNMPTRAP_INDEX]="true"
			else
				DCISM_FEATURES_ENABLED_ARRAY[$SNMPTRAP_INDEX]="false"
			fi
			${IBIA_SCRIPT} get-status | grep -i enabled >> /dev/null 2>&1
            if [ $? == 0 ]; then
                DCISM_FEATURES_ENABLED_ARRAY[$OS2IDRAC_INDEX]="true"
            else
                DCISM_FEATURES_ENABLED_ARRAY[$OS2IDRAC_INDEX]="false"
            fi
		fi
	fi

    # process any options passed
    if [ $# -le 2 ]; then
        if [ "$1" == "-a" -o "$1" == "-i" ] && [ "$2" == "-a" -o "$2" == "-i" ]; then
		    PREDEFINE_OPTION=1
		fi
    fi
    if [ $# -gt 0 ];
    then
      # process options
     ValidateOpts $*
    fi

    # process any options passed
    #as MOD_CM Contains filtered command line options i.e other than --prefix
    if [  -n "${MOD_CM}" ]; then

      # if already installed, should be able to add comps OR upgrade
#      DetectPreviousInstall "silent"

      # install or uninstall
		if [ $SHORT_DEL == "true" ]
		then
				UninstallPackageSilent
		else
			if [ "$SCRIPT_SOURCE" == "sbin" ]; then
				echo "Installer files not found in expected location .. Cannot continue with install options $MOD_CM .. "
				exit $ERROR
			fi
			#check for install/upgrade in silent mode for mutlogger
			if [ $UPGRADE -ne 1 ]; then
                setMUTlog 0 #install
			else
                setMUTlog 2 #upgrade
			fi
			InstallPackageSilent
		fi
    else
      # clear screen and print greetings
            clear
     # PrintGreetings
        PrintGreetings
      # list the optional features that user can choose from
            ShowInstallOptions
      # read users input on the optional packages
            TakeUsersInputOnOptions
          # if the install or upgrade was successful, run post install
                PerformPostInstall
    fi
}

GetPathToScript $0

Main $* 2>&1

exit $UPDATE_SUCCESS

