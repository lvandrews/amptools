#!/usr/bin/env bash
#
#  ancomR.sh - Test a biom-formatted OTU table in the R package ANCOM according to a QIIME-formatted mapping file and supplied factor
#
#  Version 1.0.0 (February, 17, 2016)
#
#  Copyright (c) 2015 Andrew Krohn
#
#  This software is provided 'as-is', without any express or implied
#  warranty. In no event will the authors be held liable for any damages
#  arising from the use of this software.
#
#  Permission is granted to anyone to use this software for any purpose,
#  including commercial applications, and to alter it and redistribute it
#  freely, subject to the following restrictions:
#
#  1. The origin of this software must not be misrepresented; you must not
#     claim that you wrote the original software. If you use this software
#     in a product, an acknowledgment in the product documentation would be
#     appreciated but is not required.
#  2. Altered source versions must be plainly marked as such, and must not be
#     misrepresented as being the original software.
#  3. This notice may not be removed or altered from any source distribution.
#
#set -e

## Trap function on exit.
function finish {
if [[ -f $tempfile0 ]]; then
	rm $tempfile0
fi
if [[ -f $tempfile1 ]]; then
	rm $tempfile1
fi
if [[ -f $tempfile2 ]]; then
	rm $tempfile2
fi
if [[ -f $tempfile3 ]]; then
	rm $tempfile3
fi
if [[ -f $tempfile4 ]]; then
	rm $tempfile4
fi
if [[ -f $tempfile5 ]]; then
	rm $tempfile5
fi
if [[ -f $tempfile6 ]]; then
	rm $tempfile6
fi
if [[ -f $biomtemp ]]; then
	rm $biomtemp
fi

}
trap finish EXIT

## Set variables
	scriptdir="$( cd "$( dirname "$0" )" && pwd )"
	repodir=$(dirname $scriptdir)
	workdir=$(pwd)
	tempdir="$repodir/temp"
	randcode=`cat /dev/urandom |tr -dc 'a-zA-Z0-9' | fold -w 8 | head -n 1` 2>/dev/null
	tempfile0="$tempdir/$randcode.convert0.temp"
	tempfile1="$tempdir/$randcode.convert1.temp"
	tempfile2="$tempdir/$randcode.convert2.temp"
	tempfile3="$tempdir/$randcode.map.temp"
	tempfile4="$tempdir/$randcode.convert4.temp"
	tempfile5="$tempdir/$randcode.convert5.temp"
	tempfile6="$tempdir/$randcode.convert6.temp"
	biomtemp="$tempdir/$randcode.biom.temp"
	input="$1"
	map="$2"
	factor="$3"

	date0=$(date +%Y%m%d_%I%M%p)

	bold=$(tput bold)
	normal=$(tput sgr0)
	underline=$(tput smul)

## Check whether user had supplied -h or --help. If yes display help 
	if [[ "$1" == "--help" ]] || [[ "$1" == "-h" ]]; then
	less $repodir/docs/ancomR.help
		exit 0
	fi

## If incorrect number of arguments supplied, display usage 
	if [[ "$#" -ne 3 ]]; then 
	cat $repodir/docs/ancomR.usage
		exit 1
	fi 

## Test for presence of datamash
	dmtest=$(command -v datamash | wc -l)
	if [[ "$datamash" == "0" ]]; then
	echo "
This script requires the datamash utility to run. Ensure the command is in your
PATH before running this script again.
You can obtain datamash here: https://www.gnu.org/software/datamash/download/
Or run (or rerun) the akutils_ubuntu_installer: https://github.com/alk224/akutils_ubuntu_installer
Exiting.
	"
	exit 1
	fi

## Parse input file
	inbase=$(basename $input .biom)
	inext="${1##*.}"
	inpath="${1%.*}"
	inname="${inpath##*/}"
	indir=$(dirname $1)
	outdir="$workdir/ANCOM_${inbase}/"

	mkdir -p $outdir

## Test for valid input
	if [[ ! -f $input ]]; then
		echo "
Input file not found. Check your spelling and re-enter command.
Exiting.
		"
		exit 1
	fi
	if [[ "$inext" != "biom" ]]; then
		echo "
Input file does not have valid extension. Input must have biom extension.
Exiting.
		"
		exit 1
	fi
		if [[ ! -f $map ]]; then
		echo "
Mapping file not found. Check your spelling and re-enter command.
Exiting.
		"
		exit 1
	fi

## Check if supplied factor is valid according to mapping file or exit
	factortest=$(head -1 $map | grep -w $factor | wc -l)
	if [[ "$factortest" -ne "1" ]]; then
		echo "
Supplied factor not found in mapping file. Check your spelling and re-enter
command. Exiting.
		"
		exit 1
	fi

## Convert biom file to txt and copy to tempdir for processing
	biomtotxt.sh $input &>/dev/null
	mv $indir/$inbase.txt $tempfile0

## Test for initial header in some converted OTU tables and remove as necessary
	headtest=$(grep "Constructed from biom file" $tempfile0 2>/dev/null | wc -l)
	if [[ "$headtest" -ge "1" ]]; then
		sed -i '/# Constructed from biom file/d' $tempfile0
	fi

## Change OTU ID to Group
	sed -i 's/#OTU ID/Group/' $tempfile0

## Get column from OTU table that contains the taxonomy string
	column0=`awk -v table="$tempfile0" '{ for(i=1;i<=NF;i++){if ($i ~ /taxonomy/) {print i}}}' $tempfile0`
	column1=`expr $column0 - 2`

## Get factor column from map file and make tempfile to relate sample ID to factor
	fact=`awk -v factor="$factor" -v map="$map" '{ for(i=1;i<=NF;i++){if ($i == factor) {print i}}}' $map`

	grep -v "#" $map | cut -f1,${fact} > $tempfile3

## Remove taxonomy field
	cat $tempfile0 | cut -f1-${column1} > $tempfile1

## If this is a summarized table, remove all but the deepest taxonomic identifier (using semicolon as delimiter)
	sctest=$(cat $tempfile1 | cut -f1 | grep ";" | wc -l)
	if [[ "$sctest" -ge "1" ]]; then
		sed -i "s/^.\+;//g" $tempfile1
	fi

## Transpose table
	datamash transpose < $tempfile1 > $tempfile2

## Replace sample IDs with factor according to mapping file
	for line in `cat $tempfile3 | cut -f1`; do
		linetest=$(grep -w $line $tempfile2 | wc -l)
		if [[ $linetest -ge 1 ]]; then
		new=`grep -w $line $tempfile3 | cut -f2`
		sed -i "s/^$line\s/$new\t/" $tempfile2
		fi
	done

## Move first column to end, writing to output
	numcols=`awk '{print NF}' $tempfile2 | tail -n1`
	cat $tempfile2 | cut -f1 > $tempfile4
	cat $tempfile2 | cut -f2-${numcols} > $tempfile5
	paste $tempfile5 $tempfile4 > $tempfile6

echo "Ancom-friendly conversion complete.
Beginning statistical comparisons. Please be patient.
"

## Run ancom.R
	Rscript $scriptdir/ancomR.r $tempfile6 $factor $outdir &>/dev/null

## Test for output, print completion and outputs, remove unwanted files
	uncortest=$(grep "No significant OTUs detected" $outdir/ANCOM_detections_${factor}_uncorrected.txt | wc -l)
	fdrtest=$(grep "No significant OTUs detected" $outdir/ANCOM_detections_${factor}_FDRcorrected.txt | wc -l)
		uncorout="ANCOM_${factor}_uncorrected.pdf"
		uncorpdf="ANCOM_${factor}_uncorrected.pdf"
		fdrout="ANCOM_${factor}_FDRcorrected.pdf"
		fdrpdf="ANCOM_${factor}_FDRcorrected.pdf"
	if [[ "$uncortest" == 1 ]]; then
		rm $outdir/$uncorpdf
		uncorpdf="No significant OTUs detected"
	fi
	if [[ "$fdrtest" == 1 ]]; then
		rm $outdir/$fdrpdf
		fdrpdf="No significant OTUs detected"
	fi
	if [[ -f "Rplots.pdf" ]]; then
		rm Rplots.pdf
	fi

echo "Comparisons complete.
Output directory: $outdir
Uncorrected results: $uncorout
Uncorrected plots: $uncorpdf
FDR-corrected output: $fdrout
FDR-corrected plots: $fdrpdf
"

exit 0
