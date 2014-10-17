#!/bin/bash
##### citrixrawconvert.sh
##    copyright 2012 Theral Mackey, Evernote Inc. tmackey@evernote.com
##    License: GPL: Free to use/modify/distribute so long as this attribute/licensing remains
##   ***PROVIDED AS AN EXAMPLE, EDUCATIONAL USE ONLY, USE AT YOUR OWN RISK ***
##    v0.2.1
##    Given a domU (xen guest) running on Citrix Xen, this script takes a snapshot of a VM
##    and generates raw disk images suitable for use with normal Open Xen as from the
##    xen.org project. This script was created on XenServer release 5.6.100-39215p (xenenterprise)
##    and assumes snapshots can be taken (we use LVM vols for storage to make it easy)
##
##    To use: give it the name of a domu. It will create 1 image per virtual drive as:
##    ${DUMPPATH}/${domuname}-files/${domuname}-${REF}.RAW.img  each containing
##    a VHD style disk image of the VM drives (same format you would get from dd'ing a whole drive
##    instead of a partition (you want this for windows VMs)). It has an option (enabled by default) that
##    uses kpartx to mount this image as its component partitions in /dev/mapper as loop devs
##    ${DUMPPATH} will need space for the image and conversion files to fit, 
##    and should not have an existing ${DOMU}-files/ directory in it.
##    The resulting image files are sparse.
## 
##    NOTE: It requires python, and the xenmigrate.py script from Jolokia Networks, available here:
##    http://pastebin.com/MK5Da8CB (patched by bret.miller) and put in /usr/local/bin
##    Original (needs patching):
##    http://jolokianetworks.com/Virtualization/Converting_from_Citrix_XenServer_to_Xen_open_source
##   
#####

DOMU=$1
## Where to dump the conversion files, do not set to '/'!
DUMPPATH='/var/tmp'
## Use kpartx to mount the partitions?
KPARTX='YES'

if [[ -z "${DOMU}" ]] ; then
  echo "Usage: citrixrawconvert.sh <domu-name>"
  echo "  domu-name is the name of the running domu, not its UUID or volume ID"
fi
if [[ -z "${DUMPPATH}" || "${DUMPPATH}" == '/' ]] ; then
  echo "Please do not run this in / !!! Edit and change DUMPPATH."
  exit 1
fi
UUID=`xe vm-list | grep -A2 -B2 ${DOMU} | grep uuid | cut -f2 -d: | sed -e 's/\s*//g'`
echo "UUID ${UUID}"
if [[ -z "${UUID}" ]] ; then
  echo "Error! Could not find a VM by the name ${DOMU}!"
  exit 1
fi
mkdir -p ${DUMPPATH}/${DOMU}-files
cd ${DUMPPATH}/${DOMU}-files
echo "Snapping VM, exporting xva image"
SNAPVM=`xe vm-snapshot vm=${UUID} new-name-label=${DOMU}-snap`
xe template-param-set is-a-template=false ha-always-run=false uuid=${SNAPVM}
xe vm-export vm=${SNAPVM} filename=${DUMPPATH}/${DOMU}-files/${DOMU}-img.xva
xe vm-uninstall uuid=${SNAPVM} force=true
echo "Unpacking xva image..."
tar -xf ${DUMPPATH}/${DOMU}-files/${DOMU}-img.xva 2>/dev/null
for DIR in `ls -1 ${DUMPPATH}/${DOMU}-files/ | grep '^Ref:' ` ; do
  REF=${DIR#Ref:}
  if [[ -n "${DIR}" ]] ; then
    rm -f ${DUMPPATH}/${DOMU}-files/${DOMU}-img.xva
    echo "Converting ${DIR} to raw"
    python /usr/local/bin/xenmigrate.py --convert=${DUMPPATH}/${DOMU}-files/${DIR} ${DUMPPATH}/${DOMU}-files/${DOMU}-${REF}.RAW.img
    rm -rf ${DUMPPATH}/${DOMU}-files/${DIR}
  fi

  if [[ "${KPARTX}" -eq 'YES' ]] ; then
    echo "Mounting partitions via loop devs"
    kpartx -v -a ${DUMPPATH}/${DOMU}-files/${DOMU}-${REF}.RAW.img
  fi
done
echo "done!"


