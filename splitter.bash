#!/bin/bash

#
#    pipeline  Consensus assembly and allele interpretation pipeline.
#    Copyright (c) 2014 National Marrow Donor Program (NMDP)
#
#    This library is free software; you can redistribute it and/or modify it
#    under the terms of the GNU Lesser General Public License as published
#    by the Free Software Foundation; either version 3 of the License, or (at
#    your option) any later version.
#
#    This library is distributed in the hope that it will be useful, but WITHOUT
#    ANY WARRANTY; with out even the implied warranty of MERCHANTABILITY or
#    FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
#    License for more details.
#
#    You should have received a copy of the GNU Lesser General Public License
#    along with this library;  if not, write to the Free Software Foundation,
#    Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307  USA.
#
#    > http://www.gnu.org/licenses/lgpl.html
#

MYPID=$$
DEBUG=0  #change to 1 to increase verbosity and leave workfiles behind
MASTERWORKFILE=fullfile.$MYPID
SCRATCHFILE=scratch.$MYPID
TOOLPATH="$(pwd)"  #default to cwd if not specified
WORKDIR="$1"  #our data dir is argument one
DEBUG="$2"  #take debug mode as argument two 

if [[ "${TOOLPATH}" == "$(pwd)" ]]; then 
  echo "TOOLPATH is the variable that must contain the path to your workerscript,"
  echo "which defaults to 'process_fastq.sh'.  This value can be altered by "
  echo "editing $0 and setting TOOLPATH correctly."
  echo "You have specified TOOLPATH as ${TOOLPATH}.  Is this REALLY correct? (y|n)"
  read goahead
  if [[ ${goahead}"x" != "yx" ]]; then
    echo "edit splitter.bash to have the desired TOOLPATH.  It should point to"
    echo "the directory containing process_fastq.bash"
    exit 1
  fi
fi
export goahead=""

if [[ ${WORKDIR}"x" == "x" ]]; then
  echo "location of work directory MUST be the first argument to this script."
  exit 1
fi

if [[ $DEBUG"x" != "x" ]]; then
	echo "debug mode enabled.  verbosity cranked."
  echo "WORKDIR = ${WORKDIR}"
fi

RAWDIR="${WORKDIR}/raw"
WORKERSCRIPT="${TOOLPATH}/process_fastq.bash"

if [[ ! -x ${WORKERSCRIPT} ]]; then
  echo "sorry, you specified a worker script (${WORKERSCRIPT}) which cannot be executed."
  exit 1
fi

INTERM="${WORKDIR}/intermediate"
FINAL="${WORKDIR}/final"
ABORT=0

##try to find all permission/directory existence issues
## in one pass, then spit out all the dir things that we found wrong.

for DIR in ${INTERM} ${FINAL} ${RAWDIR}; do
  if [[ ! -d ${DIR} ]]; then
    echo "directory ${DIR} must exist to proceed"
    let ABORT=ABORT+1
  fi
done

for DIR in ${INTERM} ${FINAL}; do
  if [[ ! -w ${DIR} ]]; then
    echo "directory ${DIR} must be writable (for you) to proceed"
    let ABORT=ABORT+1
  fi
  if [[ ! -x ${DIR} ]]; then
    echo "directory ${DIR} must be executable (for you) to proceed"
    let ABORT=ABORT+1
  fi
done

if [[ $ABORT -gt 0 ]]; then
  echo "exiting due to errors"
  exit 1
fi

if [[ $(find ${RAWDIR} -type f | grep -c fastq) -eq 0 ]]; then
  echo "no fastq files found in ${RAWDIR}.  Aborting."
  exit 1
fi

for DIR in ${INTERM} ${FINAL}; do
  if [[ $(ls ${DIR} | wc -l) -gt 0 ]]; then
    export goahead=""
    echo "Files already exist in ${DIR} -- enter 'y' to proceed and overwrite:"
    read goahead
    if [[ ${goahead}"x" != "yx" ]]; then
      exit 1
    fi
  fi
done

#  clean up before we start, in case we were interrupted last time
rm ${MASTERWORKFILE}  2>/dev/null
rm ${SCRATCHFILE}  2>/dev/null
if [[ ${DEBUG}"x" != "x" ]]; then
  echo "MASTERWORKFILE = ${MASTERWORKFILE}"
fi
for MYIDENTIFIER in $(find ${RAWDIR} -name '*.fastq' -print -type f | sed -e 's/R[12]/RX/g' | uniq); do if [[ ${DEBUG}"x" == "1x" ]]; then
    echo ${MYIDENTIFIER}
  fi
  echo ${MYIDENTIFIER} >> ${SCRATCHFILE}
  ## this should give us a unique list
  ## yes, this is a bit pathological, but duplicating
  ## entries could lead to two separate processing threads
  ## running on the same fastq file.  potentially ugly.
done

sort -u ${SCRATCHFILE} > ${MASTERWORKFILE}

let NUMCPU=$(cat /proc/cpuinfo | grep -cw processor)
echo "preparing to divide work evenly among ${NUMCPU} cores"

split ${MASTERWORKFILE} -n l/${NUMCPU} -d -e ${MYPID}

## now, time to call the worker script

if [ -f nohup.out ]; then
  rm nohup.out
fi

for file in $(find . -name "${MYPID}*" -type f -print); do
  BASEFILENAME=$(echo ${file} | awk -F\/ '{print $NF}')
  nohup time ${WORKERSCRIPT} ${file} ${DEBUG} >> timedata.${BASEFILENAME} &
done

if [[ ${DEBUG}"x" == "x" ]]; then
  #delete scratchfile and workfile unless we're in debug mode
  rm ${MASTERWORKFILE} ${SCRATCHFILE} 2>/dev/null
fi
