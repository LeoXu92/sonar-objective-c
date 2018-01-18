#!/bin/bash
## INSTALLATION: script to copy in your Xcode project in the same directory as the .xcodeproj file
## USAGE: ./run-sonar.sh
## DEBUG: ./run-sonar.sh -v
## WARNING: edit your project parameters in sonar-project.properties rather than modifying this script
#

trap "echo 'Script interrupted by Ctrl+C'; stopProgress; exit 1" SIGHUP SIGINT SIGTERM

function testIsInstalled() {

	hash $1 2>/dev/null
	if [ $? -eq 1 ]; then
		echo >&2 "ERROR - $1 is not installed or not in your PATH"; exit 1;
	fi
}

function readParameter() {
	
	variable=$1
	shift
	parameter=$1
	shift

	eval $variable="\"$(sed '/^\#/d' sonar-project.properties | grep $parameter | tail -n 1 | cut -d '=' -f2- | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')\""
}

# Run a set of commands with logging and error handling
function runCommand() {

	# 1st arg: redirect stdout 
	# 2nd arg: command to run
	# 3rd..nth arg: args
	redirect=$1
	shift

	command=$1
	shift
	
	if [ "$nflag" = "on" ]; then
		# don't execute command, just echo it
		echo
		if [ "$redirect" = "/dev/stdout" ]; then	
			if [ "$vflag" = "on" ]; then
				echo "+" $command "$@"
			else
				echo "+" $command "$@" "> /dev/null"
			fi
		elif [ "$redirect" != "no" ]; then
			echo "+" $command "$@" "> $redirect"
		else
			echo "+" $command "$@"
		fi
		
	elif [ "$vflag" = "on" ]; then
		echo

		if [ "$redirect" = "/dev/stdout" ]; then	
			set -x #echo on
			$command "$@"
			returnValue=$?	
			set +x #echo off			
		elif [ "$redirect" != "no" ]; then
			set -x #echo on
			$command "$@" > $redirect
			returnValue=$?	
			set +x #echo off			
		else
			set -x #echo on
			$command "$@"
			returnValue=$?	
			set +x #echo off			
		fi
		
		if [[ $returnValue != 0 && $returnValue != 5 ]] ; then
			stopProgress
			echo "ERROR - Command '$command $@' failed with error code: $returnValue"
			exit $returnValue
		fi
	else
		echo "--------------------------------"
		echo $command
		echo "$@"
		if [ "$redirect" = "/dev/stdout" ]; then	
			$command "$@" > /dev/null
		elif [ "$redirect" != "no" ]; then
			$command "$@" > $redirect
		else
			$command "$@"
		fi

        returnValue=$?
		if [[ $returnValue != 0 && $returnValue != 5 ]] ; then
			stopProgress
			echo "ERROR - Command '$command $@' failed with error code: $returnValue"
			exit $?
		fi

	
		echo	
	fi	
}

## COMMAND LINE OPTIONS
vflag=""
nflag=""
oclint="on"
while [ $# -gt 0 ]
do
    case "$1" in
    -v)	vflag=on;;
    -n) nflag=on;;
	-nooclint) oclint="";;	    
	--)	shift; break;;
	-*)
        echo >&2 "Usage: $0 [-v]"
		exit 1;;
	*)	break;;		# terminate while loop
    esac
    shift
done

# Usage OK
echo "Running run-sonar.sh..."

# 检查依赖是否已经安装 xcpretty and oclint
testIsInstalled xcpretty
testIsInstalled oclint

# 检查有没有 sonar-project.properties 文件
if [ ! -f sonar-project.properties ]; then
	echo >&2 "ERROR - No sonar-project.properties in current directory"; exit 1;
fi

# 从 sonar-project.properties 读出参数

# .xcworkspace/.xcodeproj filename
workspaceFile=''; readParameter workspaceFile 'sonar.objectivec.workspace'
projectFile=''; readParameter projectFile 'sonar.objectivec.project'
# 源文件
srcDirs=''; readParameter srcDirs 'sonar.sources'
# Scheme
appScheme=''; readParameter appScheme 'sonar.objectivec.appScheme'
# test 
testScheme=''; readParameter testScheme 'sonar.objectivec.testScheme'

if [ "$vflag" = "on" ]; then
 	echo "Xcode workspace file is: $workspaceFile"
 	echo "Xcode project file is: $projectFile"
 	echo "Xcode application scheme is: $appScheme"
 	echo "Xcode test scheme is: $testScheme"
fi

# 检查必须参数
if [ -z "$projectFile" -o "$projectFile" = " " ]; then
	if [ ! -z "$workspaceFile" -a "$workspaceFile" != " " ]; then
		echo >&2 "ERROR - sonar.objectivec.project parameter is missing in sonar-project.properties. You must specify which projects (comma-separated list) are application code within the workspace $workspaceFile."
	else
		echo >&2 "ERROR - sonar.objectivec.project parameter is missing in sonar-project.properties (name of your .xcodeproj)"
	fi
	exit 1
fi
if [ -z "$srcDirs" -o "$srcDirs" = " " ]; then
	echo >&2 "ERROR - sonar.sources parameter is missing in sonar-project.properties. You must specify which directories contain your .h/.m source files (comma-separated list)."
	exit 1
fi
if [ -z "$appScheme" -o "$appScheme" = " " ]; then
	echo >&2 "ERROR - sonar.objectivec.appScheme parameter is missing in sonar-project.properties. You must specify which scheme is used to build your application."
	exit 1
fi

## SCRIPT

# Create sonar-reports/ for reports output

if [[ ! (-d "sonar-reports") && ("$nflag" != "on") ]]; then
	if [ "$vflag" = "on" ]; then
		echo 'Creating directory sonar-reports/'
	fi
	mkdir sonar-reports
	if [[ $? != 0 ]] ; then
		stopProgress
    	exit $?
	fi
fi

# Extracting project information needed later
echo 'Extracting Xcode project information'
xcodebuild clean

export LC_ALL="en_US.UTF-8"
if [[ "$workspaceFile" != "" ]] ; then
	echo "xcodebuild clean"
	xcodebuild clean -workspace "${workspaceFile}" -scheme "${appScheme}" -sdk iphonesimulator -configuration Release
	echo "xcodebuild analyze"
	xcodebuild -workspace "${workspaceFile}" -scheme "${appScheme}" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 6' ONLY_ACTIVE_ARCH=NO -configuration build | tee xcodebuild.log | xcpretty -r json-compilation-database --output compile_commands.json
else
	echo "xcodebuild clean"
	xcodebuild clean -project "${projectFile}" -scheme "${appScheme}" -configuration Release
	echo "xcodebuild analyze"
	xcodebuild -project "${projectFile}" -scheme "${appScheme}" -sdk iphonesimulator -destination 'platform=iOS Simulator,name=iPhone 6' ONLY_ACTIVE_ARCH=NO -configuration build | tee xcodebuild.log | xcpretty -r json-compilation-database --output compile_commands.json
fi


if [ "$oclint" = "on" ]; then

	# OCLint
	echo -n 'Running OCLint...'

	# Build the --include flags
	currentDirectory=${PWD##*/}
	includedCommandLineFlags=""
	echo "$srcDirs" | sed -n 1'p' | tr ',' '\n' > tmpFileRunSonarSh
	while read word; do
		includedCommandLineFlags+=" --include .*/${currentDirectory}/${word}"
	done < tmpFileRunSonarSh
	rm -rf tmpFileRunSonarSh
	if [ "$vflag" = "on" ]; then
		echo
		echo -n "Path included in oclint analysis is:$includedCommandLineFlags"
	fi
	
	# Run OCLint with the right set of compiler options
    maxPriority=10000
	oclint-json-compilation-database -- -max-priority-1 $maxPriority -max-priority-2 $maxPriority -max-priority-3 $maxPriority -rc LONG_LINE=150 -report-type pmd -o sonar-reports/oclint.xml

else
	echo 'Skipping OCLint (test purposes only!)'
fi

# SonarQube
echo 'Running SonarQube using SonarQube Scanner'
sonar-scanner

exit 0