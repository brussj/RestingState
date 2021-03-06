#!/bin/bash

##################################################################################################################
# Time Series Correlation from Seed/ROI masks
#     1. Push Seed masks from MNI to EPI space
#     2. Calculate Time-series for each Seed of interest
#     3. Time-Series Correlation/Zmap Creation
#     4. Seed zmap QC (push to highres (T1) and standard (MNI)
##################################################################################################################

nuisancefeat=nuisancereg.feat
melodicfeat=melodic.ica

##Check of all ROIs (from ROIs directory), that can be used for seeding
scriptPath=`perl -e 'use Cwd "abs_path";print abs_path(shift)' $0`
scriptDir=`dirname $scriptPath`
knownRois=`ls -1 $scriptDir/ROIs/*nii* | awk -F"/" '{print $NF}' | awk -F"." '{print $1}'`


function printCommandLine {
  echo "Usage: seedVoxelCorrelation.sh -E restingStateImage -r roi -m motionScrubFlag -f -V"
  echo " where"
  echo "   -E resting state image"
  echo "        *Top-level RestingState.nii.gz image"
  echo "   -m use MotionScrub EPI: O,1 or 2 (default is 0/no)"
  echo "      0 = use non-motionscrubbed EPI only (default)"
  echo "      1 = use motionscrubbed EPI only"
  echo "      2 = use motionscrubbed and non-motionscrubbed EPI (parallel output)"
  echo "   -r roi for seed voxel (can be used multiple times)"
  echo "        *e.g. -r pccrsp -r icalc"
  echo "   -R Data file with seed list, one seed per line"
  echo "        **Use ONLY one option, -r or -R, NOT both"
  echo "   -f (fieldMap registration correction)"
  echo "        *Only set this flag if FieldMap correction was used during qualityCheck"
  echo "        **This affects only the EPI to T1 QC images (invoked via '-V')"
  echo "   -V Review Results (default is to NOT view results).  Setting of this flag will spit out time-series plots of seed/ROI"
  echo ""
  echo "Existing seeds:"
  echo "$knownRois"  
  exit 1
}


# Parse Command line arguments
while getopts “hE:m:r:R:fV” OPTION
do
  case $OPTION in
    h)
      printCommandLine
      ;;
    E)
      epiData=$OPTARG
      ;;
    m)
      motionscrubFlag=$OPTARG
      ;;
    r)
      roiList=`echo $roiList $OPTARG`
      roiInd=1
      ;;
    R)
      roiList=`cat $OPTARG`
      roiInFile=$OPTARG
      ;;
    f)
      fieldMapFlag=1
      ;;
    V)
      reviewResults=1
      ;;
    ?)
      echo "ERROR: Invalid option"
      printCommandLine
      ;;
     esac
done


  #A few default parameters (if input not specified, these parameters are assumed)
  if [[ $reviewResults == "" ]]; then
    reviewResults=0
  fi

  if [[ $motionscrubFlag == "" ]]; then
    motionscrubFlag=0
  fi

  if [[ $fieldMapFlag == "" ]]; then
    fieldMapFlag=0
  fi



for roi in $roiList
do
  testRoi=`echo $knownRois | grep $roi`
  if [ "$testRoi" == "" ]; then
    echo "Error: Invalid ROI specified (${roi})"
    echo "Valids ROIs: $knownRois"
    exit 1
  fi
done

if [[ "$roiList" == "" ]]; then
  echo "Error: At least one ROI must be specified using the -r option."
  exit 1
fi

if [[ "$epiData" == "" ]]; then
  echo "Error: The restingStateImage (-E) is a required option."
  exit 1
fi



#If new seeds are added, echo them out to the rsParams file (only if they don't already exist in the file)
  #Making a *strong* assumption that any ROI lists added after initial processing won't reuse the first ROI (e.g. pccrsp)
indir=`dirname $epiData`
seedTestBase=`cat $indir/rsParams | grep "seeds=" | awk -F"=" '{print $2}' | awk -F"-r " '{for (i=2; i<=NF; i++) print $i}'`
seedTest=`echo $seedTestBase | awk '{print $1}'`
roiTest=`echo $roiList | awk '{print $1}'`

for i in $roiList
do
  seeds="$seeds -r $i"
done

if [[ "$seedTest" != "$roiTest" ]]; then
  echo "seeds=$seeds" >> $indir/rsParams
fi




subjectDir=`dirname $indir`
roiDir=${scriptDir}/ROIs
#epiwarpDir=$indir/EPItoT1optimized
#t1warpDir=$indir/T1forWarp

if [ $motionscrubFlag == 0 ]; then
  filename=run_firstlevelseeding_parallel.m
elif [ $motionscrubFlag = 1 ]; then
  filename2=run_firstlevelseeding_parallel_ms.m
else
  filename=run_firstlevelseeding_parallel.m
  filename2=run_firstlevelseeding_parallel_ms.m
fi


##Echo out all input parameters into a log
logDir=$indir
echo "$scriptPath" >> $logDir/rsParams_log
echo "------------------------------------" >> $logDir/rsParams_log
echo "-E $epiData" >> $logDir/rsParams_log
echo "-m $motionscrubFlag" >> $logDir/rsParams_log
if [[ $roiInd == 1 ]]; then
  echo "$seeds" >> $logDir/rsParams_log
else
  echo "-R $roiInFile" >> $logDir/rsParams_log
fi
if [[ $fieldMapFlag == 1 ]]; then
  echo "-f" >> $logDir/rsParams_log
fi
if [[ $reviewResults == 1 ]]; then
  echo "-V" >> $logDir/rsParams_log
fi
echo "`date`" >> $logDir/rsParams_log
echo "" >> $logDir/rsParams_log
echo "" >> $logDir/rsParams_log



    

echo "Running $0 ..."

#### Mapping ROIs To Functional Space ############
echo "...Transforming ROIs to EPI space"

cd $indir

if [ -e $indir/seeds.txt ]; then
  rm $indir/seeds.txt
fi

# Map the ROIs
for roi in $roiList
do
  echo "......Mapping $roi from MNI (standard) to subject EPI (func) space"


  #Source MNI to EPI warp file
  MNItoEPIWarp=`cat $indir/rsParams | grep "MNItoEPIWarp=" | tail -1 | awk -F"=" '{print $2}'`

  #Apply the nonlinear warp from MNI to EPI
  applywarp --ref=${epiData} --in=${roiDir}/${roi}.nii.gz --out=${nuisancefeat}/stats/${roi}_mask.nii.gz --warp=${MNItoEPIWarp} --datatype=float

  #Threshold and binarize output	    
  fslmaths ${nuisancefeat}/stats/${roi}_mask.nii.gz -thr 0.5 ${nuisancefeat}/stats/${roi}_mask.nii.gz
  fslmaths ${nuisancefeat}/stats/${roi}_mask.nii.gz -bin ${nuisancefeat}/stats/${roi}_mask.nii.gz

  #Check to see that resultant, warped file has any volume (if seed is too small, warped output may have a zero volume)

  seedVol=`fslstats ${nuisancefeat}/stats/${roi}_mask.nii.gz -V | awk '{print $2}'`
    if [[ $seedVol == 0.000000 ]]; then
      echo "$roi >> ${nuisancefeat}/stats/seedsTooSmall"
      rm ${nuisancefeat}/stats/${roi}_mask.nii.gz
    else
      # Account for $motionscrubFlag
        # Extract the time-series per ROI
        # Will need the "normal" time-series, regardless of motion-scrubbing flag so, if condition = 1 or 2, write out regular time-series
      if [[ $motionscrubFlag == 0 ]]; then	   
        fslmeants -i ${nuisancefeat}/stats/res4d_normandscaled -o ${nuisancefeat}/stats/${roi}_residvol_ts.txt -m ${nuisancefeat}/stats/${roi}_mask.nii.gz
      elif [[ $motionscrubFlag == 1 ]]; then
        fslmeants -i ${nuisancefeat}/stats/res4d_normandscaled_motionscrubbed -o ${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt -m ${nuisancefeat}/stats/${roi}_mask.nii.gz
      else
        fslmeants -i ${nuisancefeat}/stats/res4d_normandscaled -o ${nuisancefeat}/stats/${roi}_residvol_ts.txt -m ${nuisancefeat}/stats/${roi}_mask.nii.gz
        fslmeants -i ${nuisancefeat}/stats/res4d_normandscaled_motionscrubbed -o ${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt -m ${nuisancefeat}/stats/${roi}_mask.nii.gz
      fi

      #Output of fslmeants is a text file with space-delimited values.  There is only one "true" ts value (first column) and the blank space is interpreted as a "0" value in matlab.  Write to temp file then move (rewrite original)
      if [[ $motionscrubFlag == 0 ]]; then
        cat ${nuisancefeat}/stats/${roi}_residvol_ts.txt | awk '{print $1}' > ${nuisancefeat}/stats/temp_${roi}_residvol_ts.txt
        mv ${nuisancefeat}/stats/temp_${roi}_residvol_ts.txt ${nuisancefeat}/stats/${roi}_residvol_ts.txt
      elif [[ $motionscrubFlag == 1 ]]; then
        cat ${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | awk '{print $1}' > ${nuisancefeat}/stats/temp_${roi}_residvol_ms_ts.txt
        mv ${nuisancefeat}/stats/temp_${roi}_residvol_ms_ts.txt ${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt
      else
        cat ${nuisancefeat}/stats/${roi}_residvol_ts.txt | awk '{print $1}' > ${nuisancefeat}/stats/temp_${roi}_residvol_ts.txt
        cat ${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | awk '{print $1}' > ${nuisancefeat}/stats/temp_${roi}_residvol_ms_ts.txt
        mv ${nuisancefeat}/stats/temp_${roi}_residvol_ts.txt ${nuisancefeat}/stats/${roi}_residvol_ts.txt
        mv ${nuisancefeat}/stats/temp_${roi}_residvol_ms_ts.txt ${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt
      fi
  
      echo "$roi" >> $indir/seeds.txt
    fi
done

roiList2=`cat $indir/seeds.txt`

#################################



#### Seed Transform QC Images ############
echo "...QC Image Setup"

###Create QC images of seed/ROI overlaid on RestingState EPI.  Place in top level directory and report in HTML file
##Create underlay/overlay NIFTI files for QC check
#Create a temp directory 
seedQCdir=$indir/$nuisancefeat/stats/seedQC
if [ ! -e $seedQCdir/temp ]; then
  mkdir -p $seedQCdir/temp
fi

#Create underlay/overlay images for each seed
for roi in $roiList2
do
  for splitdirection in x y z
  do
    echo "......Preparing $roi ($splitdirection)"

    underlayBase=$indir/mcImgMean.nii.gz
    overlayBase=$indir/$nuisancefeat/stats/${roi}_mask.nii.gz

    #Compute Center-Of-Gravity for seed mask to determine which axial slice to use for both underlay and overlay
      #Adding 0.5 to COG for xyz dimensions to handle rounding issues
      #Need to account for slices named 0007, 0017, 0107, etc. (have to be able to handle 4-digit numbers)
    if [[ $splitdirection == "x" ]]; then
      suffix=sagittal
      sliceCutTEMP=`fslstats $overlayBase -C | awk '{printf("%d\n",$1 + 0.5)}'`
      sliceCutLength=`echo $sliceCutTEMP | awk '{print length($1)}'`
      if [[ $sliceCutLength == 1 ]]; then
        sliceCut=000${sliceCutTEMP}
      elif [[ $sliceCutLength == 2 ]]; then
        sliceCut=00${sliceCutTEMP}
      else
        sliceCut=0${sliceCutTEMP}
      fi
    elif [[ $splitdirection == "y" ]]; then
      suffix=coronal
      sliceCutTEMP=`fslstats $overlayBase -C | awk '{printf("%d\n",$2 + 0.5)}'`
      sliceCutLength=`echo $sliceCutTEMP | awk '{print length($1)}'`
      if [[ $sliceCutLength == 1 ]]; then
        sliceCut=000${sliceCutTEMP}
      elif [[ $sliceCutLength == 2 ]]; then
        sliceCut=00${sliceCutTEMP}
      else
        sliceCut=0${sliceCutTEMP}
      fi
    else
      suffix=axial
      sliceCutTEMP=`fslstats $overlayBase -C | awk '{printf("%d\n",$3 + 0.5)}'`
      sliceCutLength=`echo $sliceCutTEMP | awk '{print length($1)}'`
      if [[ $sliceCutLength == 1 ]]; then
        sliceCut=000${sliceCutTEMP}
      elif [[ $sliceCutLength == 2 ]]; then
        sliceCut=00${sliceCutTEMP}
      else
        sliceCut=0${sliceCutTEMP}
      fi
    fi

    #Split apart seed mask and example EPI image
    fslsplit $underlayBase $seedQCdir/temp/underlay_split_${suffix} -${splitdirection}
    fslsplit $overlayBase $seedQCdir/temp/overlay_split_${suffix} -${splitdirection}

    #Set variables for underlay and overlay images
    underlayImage=`ls -1 $seedQCdir/temp | grep "underlay_split_${suffix}" | grep $sliceCut`
    overlayImage=`ls -1 $seedQCdir/temp | grep "overlay_split_${suffix}" | grep $sliceCut`

	
    #Copy over underlay/overlay images, uncompress
      ##Will need to check for presence of unzipped NIFTI file (from previous runs (otherwise "clobber" won't work))
    if [[ -e $seedQCdir/${roi}_underlay_${suffix}.nii ]]; then
      if [[ ! -e $seedQCdir/oldSeeds ]]; then
        mkdir $seedQCdir/oldSeeds
      fi

      mv $seedQCdir/${roi}_underlay_${suffix}.nii $seedQCdir/oldSeeds
    fi

    cp $seedQCdir/temp/$underlayImage $seedQCdir/${roi}_underlay_${suffix}.nii.gz
    #gunzip $seedQCdir/${roi}_underlay_${suffix}.nii.gz
    if [[ -e $seedQCdir/${roi}_overlay_${suffix}.nii ]]; then
      if [[ ! -e $seedQCdir/oldSeeds ]]; then
        mkdir $seedQCdir/oldSeeds
      fi

      mv $seedQCdir/${roi}_overlay_${suffix}.nii $seedQCdir/oldSeeds
    fi

    cp $seedQCdir/temp/$overlayImage $seedQCdir/${roi}_overlay_${suffix}.nii.gz
    #gunzip $seedQCdir/${roi}_overlay_${suffix}.nii.gz
    
    ##Need to reorient coronal and sagittal images in order for matlab to process correctly (axial is already OK)
    #Coronal images will also need the orientation swapped to update header AND image info
    if [ $suffix == "sagittal" ]; then
      fslswapdim $seedQCdir/${roi}_underlay_${suffix}.nii.gz y z x $seedQCdir/${roi}_underlay_${suffix}.nii.gz
      fslswapdim $seedQCdir/${roi}_overlay_${suffix}.nii.gz y z x $seedQCdir/${roi}_overlay_${suffix}.nii.gz
    elif [ $suffix == "coronal" ]; then
      fslswapdim $seedQCdir/${roi}_underlay_${suffix}.nii.gz x z y $seedQCdir/${roi}_underlay_${suffix}.nii.gz
      fslorient -swaporient $seedQCdir/${roi}_underlay_${suffix}.nii.gz
      fslswapdim $seedQCdir/${roi}_overlay_${suffix}.nii.gz x z y $seedQCdir/${roi}_overlay_${suffix}.nii.gz
      fslorient -swaporient $seedQCdir/${roi}_overlay_${suffix}.nii.gz
    fi

    #Need to gunzip the files for use with matlab
    gunzip $seedQCdir/${roi}_underlay_${suffix}.nii.gz
    gunzip $seedQCdir/${roi}_overlay_${suffix}.nii.gz
  done
done

#Create an output directory for QC seed images
seedQCOutdir=$indir/seedQC
if [ ! -e $seedQCOutdir ]; then
  mkdir $seedQCOutdir
fi


#Create overlaps of seed_mask registered to EPI space using Octave
echo "...Creating QC Images of ROI/Seed Registration To Functional Space"
filenameQC=run_seedregistrationcheck.m;
cat > $filenameQC << EOF

% It is matlab script
close all;
clear all;
addpath('${scriptDir}');
niftiScripts=['${scriptDir}','/Octave/nifti'];
addpath(niftiScripts);statsScripts=['${scriptDir}','/Octave/statistics'];
statsScripts=['${scriptDir}','/Octave/statistics'];
addpath(statsScripts);
fid=fopen('$indir/seeds.txt');
roiList=textscan(fid,'%s');
fclose(fid);
seedDir='$seedQCdir';
imageDir='$seedQCOutdir';
seedregistrationcheck(seedDir,roiList,imageDir)
quit;
EOF


# Run script using Matlab or Octave
haveMatlab=`which matlab`
if [ "$haveMatlab" == "" ]; then
  octave --no-window-system $indir/$filenameQC 
else
  matlab -nodisplay -r "run $indir/$filenameQC"
fi


#Remove temp directory of "split" files.  Keep only underaly and overlay base images
rm -rf $seedQCdir/temp

#################################



#### Output Images To HTML File ############

#Display Coronal,Sagittal,Axial on one line
  #Put header of seed type

echo "<hr>" >> ${indir}/analysisResults.html
#echo "<h2>Seed Registration QC</h2>" >> ${indir}/analysisResults.html
echo "<h2>Seed Registration QC (Neurological View, Right=Right)</h2>" >> ${indir}/analysisResults.html
for roi in $roiList2
do
  echo "<br><b>$roi</b><br>" >> ${indir}/analysisResults.html
  echo "<img src=\"$seedQCOutdir/${roi}_coronal.png\" alt=\"${roi}_coronal seed QC\"><img src=\"$seedQCOutdir/${roi}_sagittal.png\" alt=\"${roi}_sagittal seed QC\"><img src=\"$seedQCOutdir/${roi}_axial.png\" alt=\"${roi}_axial seed QC\"><br>" >> $indir/analysisResults.html
done

#################################



#### Seed Voxel Correlation (Setup) ############
echo "...Seed Voxel Correlation Setup"

#Dimensions of EPI data
numXdim=`fslinfo $epiData | grep ^dim1 | awk '{print $2}'`
numYdim=`fslinfo $epiData | grep ^dim2 | awk '{print $2}'`
numZdim=`fslinfo $epiData | grep ^dim3 | awk '{print $2}'`

#Perform the Correlation
  #Take into account $motionscrubFlag

		##Check into matlab about fixing motion-scrubbing (Power method)

if [[ $motionscrubFlag == 0 ]]; then

  # If $motionscrubFlag == 0 (no motionscrub), res4dnormandscaled never gets unzipped
  if [[ -e $indir/$nuisancefeat/stats/res4d_normandscaled.nii.gz ]]; then
    gunzip $indir/$nuisancefeat/stats/res4d_normandscaled.nii.gz
  fi

echo "...Creating Octave script"
cat > $filename << EOF
% It is matlab script
addpath('${scriptDir}')
statsScripts=['${scriptDir}','/Octave/nifti'];
addpath(statsScripts)
fid=fopen('$indir/seeds.txt');
roiList=textscan(fid,'%s');
fclose(fid);

funcvoldim=[$numXdim $numYdim ${numZdim}];
doFisherZ=1;
motion_scrub=0;
input='res4d_normandscaled.nii';

firstlevelseeding_parallel('$indir',roiList,'$nuisancefeat',funcvoldim,input,motion_scrub,doFisherZ)
quit
EOF

elif [[ $motionscrubFlag == 1 ]]; then

echo "...Creating Octave script (motionscrubbed data)"
cat > $filename2 << EOF
% It is matlab script
addpath('${scriptDir}')
statsScripts=['${scriptDir}','/Octave/nifti'];
addpath(statsScripts)
fid=fopen('$indir/seeds.txt');
roiList=textscan(fid,'%s');
fclose(fid);

funcvoldim=[$numXdim $numYdim ${numZdim}];
doFisherZ=1;
motion_scrub=1;
input='res4d_normandscaled_motionscrubbed.nii';

firstlevelseeding_parallel('$indir',roiList,'$nuisancefeat',funcvoldim,input,motion_scrub,doFisherZ)
quit
EOF

else

echo "...Creating Octave script"
cat > $filename << EOF
% It is matlab script
addpath('${scriptDir}')
statsScripts=['${scriptDir}','/Octave/nifti'];
addpath(statsScripts)
fid=fopen('$indir/seeds.txt');
roiList=textscan(fid,'%s');
fclose(fid);

funcvoldim=[$numXdim $numYdim ${numZdim}];
doFisherZ=1;
motion_scrub=0;
input='res4d_normandscaled.nii';

firstlevelseeding_parallel('$indir',roiList,'$nuisancefeat',funcvoldim,input,motion_scrub,doFisherZ)
quit
EOF

echo "...Creating Octave script (motionscrubbed data)"
cat > $filename2 << EOF
% It is matlab script
addpath('${scriptDir}')
statsScripts=['${scriptDir}','/Octave/nifti'];
addpath(statsScripts)
fid=fopen('$indir/seeds.txt');
roiList=textscan(fid,'%s');
fclose(fid);

funcvoldim=[$numXdim $numYdim ${numZdim}];
doFisherZ=1;
motion_scrub=1;
input='res4d_normandscaled_motionscrubbed.nii';

firstlevelseeding_parallel('$indir',roiList,'$nuisancefeat',funcvoldim,input,motion_scrub,doFisherZ)
quit
EOF

fi

#################################



#### Seed Voxel Correlation (Execution) ############
echo "...Correlating Seeds With Time Series Data"

  # Run script using Matlab or Octave
    # Check for $motionscrubFlag, run appropriate file(s)
haveMatlab=`which matlab`
if [[ "$haveMatlab" == "" ]]; then
  if [[ $motionscrubFlag == 0 ]]; then
    octave --no-window-system $indir/$filename
  elif [[ $motionscrubFlag == 1 ]]; then
    octave --no-window-system $indir/$filename2
  else
    octave --no-window-system $indir/$filename
    octave --no-window-system $indir/$filename2
  fi
else
  if [[ $motionscrubFlag == 0 ]]; then
    matlab -nodisplay -r "run $indir/$filename"
  elif [[ $motionscrubFlag == 1 ]]; then
    matlab -nodisplay -r "run $indir/$filename2"
  else
    matlab -nodisplay -r "run $indir/$filename"
    matlab -nodisplay -r "run $indir/$filename2"
  fi  
fi

#################################



#### Zstat Results (to T1/MNI) ############

if [ $reviewResults == 1 ]; then
  echo "...Creating zstat Results Directory"

  #Check for existence of output directory
  if [[ ! -e $indir/seedCorrelation ]]; then
    mkdir $indir/seedCorrelation
  fi

  #Copy over anatomical files to results directory
    #T1 (highres)
  cp $indir/${nuisancefeat}/reg/highres.nii.gz $indir/seedCorrelation

    #T1toMNI (highres2standard)
  cp $indir/${nuisancefeat}/reg/highres2standard.nii.gz $indir/seedCorrelation

    #MNI (standard)
  cp $indir/${nuisancefeat}/reg/standard.nii.gz $indir/seedCorrelation


  #HTML setup
  echo "<hr><h2>Seed Time Series</h2>" >> $indir/analysisResults.html

  for roi in $roiList2
  do

    echo "...Mapping Correlation For $roi To Subject T1, MNI"

    ####Adjust for motion scrubbing
    if [[ $motionscrubFlag == 0 ]]; then
      #No motionscrubbing
      if [ -e ${roi}.png ]; then
        rm ${roi}.png
      fi

      #Check for FieldMap registration correction
      if [[ $fieldMapFlag == 1 ]]; then
        #Nonlinear warp from EPI to T1
        applywarp --in=$indir/${nuisancefeat}/stats/${roi}/cope1.nii \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_highres_zmap.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/example_func2highres_warp.nii.gz \
        --datatype=float
      else
        #Affine Transform from EPI to T1
        flirt -in $indir/${nuisancefeat}/stats/${roi}/cope1.nii \
        -ref $indir/${nuisancefeat}/reg/highres.nii.gz \
        -out $indir/seedCorrelation/${roi}_highres_zmap.nii.gz \
        -applyxfm -init $indir/${nuisancefeat}/reg/example_func2highres.mat \
        -datatype float
      fi

        #Mask out data with T1 mask (create temporary binary of skull-stripped T1)
        fslmaths $indir/${nuisancefeat}/reg/highres.nii.gz -bin $indir/${nuisancefeat}/reg/highres_mask.nii.gz -odt char
        fslmaths $indir/seedCorrelation/${roi}_highres_zmap.nii.gz -mas $indir/${nuisancefeat}/reg/highres_mask.nii.gz $indir/seedCorrelation/${roi}_highres_zmap_masked.nii.gz
        rm $indir/${nuisancefeat}/reg/highres_mask.nii.gz

      #Nonlinear warp from EPI to MNI
      applywarp --in=$indir/${nuisancefeat}/stats/${roi}/cope1.nii \
      --ref=$indir/${nuisancefeat}/reg/standard.nii.gz \
      --out=$indir/seedCorrelation/${roi}_standard_zmap.nii.gz \
      --warp=$indir/${nuisancefeat}/reg/example_func2standard_warp.nii.gz \
      --datatype=float

        #Mask out data with MNI mask
        fslmaths $indir/seedCorrelation/${roi}_standard_zmap.nii.gz -mas $FSLDIR/data/standard/MNI152_T1_2mm_brain_mask.nii.gz $indir/seedCorrelation/${roi}_standard_zmap_masked.nii.gz

        #Warp seed from MNI to T1
        applywarp --in=${roiDir}/${roi}.nii.gz \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_highres.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/standard2highres_warp.nii.gz \
        --interp=nn

      #Copy over Seed ROI        
      cp ${roiDir}/${roi}.nii.gz $indir/seedCorrelation/${roi}_standard.nii.gz

      # Summarize the time series data for report
      #echo "set term png" > $indir/gnuplotCmds
      #echo "set output \"$indir/${roi}.png\"" >> $indir/gnuplotCmds
      #echo "set title \"$roi Time Series\"" >> $indir/gnuplotCmds
      #echo "set xlabel \"Time Points\"" >> $indir/gnuplotCmds
      #echo "plot \"$indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt\" with lines" >> $indir/gnuplotCmds
      #cat $indir/gnuplotCmds | gnuplot

      #Cleanup
      #rm $indir/gnuplotCmds

      ##Creating new plots with fsl_tsplot
        #~2.2% plotting difference between actual Ymin and Ymax values (higher and lower), with fsl_tsplot
      yMax=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | sort -r | tail -1 | awk '{print ($1+($1*0.0022))}'`
      yMin=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | tail -1 | awk '{print ($1-($1*0.0022))}'`

      fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt -t "$roi Time Series" -u 1 --start=1 -x 'Time Points (TR)' --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}.png

      echo "<br><img src=\"$indir/${roi}.png\" alt=\"$roi seed\"><br>" >> $indir/analysisResults.html

    elif [[ $motionscrubFlag == 1 ]]; then
      #Only motionscrubbed data
      if [ -e ${roi}_ms.png ]; then
        rm ${roi}_ms.png
      fi

      #Check for FieldMap registration correction
      if [[ $fieldMapFlag == 1 ]]; then
        #Nonlinear warp from EPI to T1
        applywarp --in=$indir/${nuisancefeat}/stats/${roi}_ms/cope1.nii \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_ms_highres_zmap.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/example_func2highres_warp.nii.gz \
        --datatype=float
      else
        #Affine Transform from EPI to T1
        flirt -in $indir/${nuisancefeat}/stats/${roi}_ms/cope1.nii \
        -ref $indir/${nuisancefeat}/reg/highres.nii.gz \
        -out $indir/seedCorrelation/${roi}_ms_highres_zmap.nii.gz \
        -applyxfm -init $indir/${nuisancefeat}/reg/example_func2highres.mat \
        -datatype float
      fi

        #Mask out data with T1 mask (create temporary binary of skull-stripped T1)
        fslmaths $indir/${nuisancefeat}/reg/highres.nii.gz -bin $indir/${nuisancefeat}/reg/highres_mask.nii.gz -odt char
        fslmaths $indir/seedCorrelation/${roi}_ms_highres_zmap.nii.gz -mas $indir/${nuisancefeat}/reg/highres_mask.nii.gz $indir/seedCorrelation/${roi}_ms_highres_zmap_masked.nii.gz
        rm $indir/${nuisancefeat}/reg/highres_mask.nii.gz

      #Nonlinear warp from EPI to MNI
      applywarp --in=$indir/${nuisancefeat}/stats/${roi}_ms/cope1.nii \
      --ref=$indir/${nuisancefeat}/reg/standard.nii.gz \
      --out=$indir/seedCorrelation/${roi}_ms_standard_zmap.nii.gz \
      --warp=$indir/${nuisancefeat}/reg/example_func2standard_warp.nii.gz \
      --datatype=float

        #Mask out data with MNI mask
        fslmaths $indir/seedCorrelation/${roi}_ms_standard_zmap.nii.gz -mas $FSLDIR/data/standard/MNI152_T1_2mm_brain_mask.nii.gz $indir/seedCorrelation/${roi}_ms_standard_zmap_masked.nii.gz

        #Warp seed from MNI to T1
        applywarp --in=${roiDir}/${roi}.nii.gz \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_highres.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/standard2highres_warp.nii.gz \
        --interp=nn

      #Copy over Seed ROI  
      cp ${roiDir}/${roi}.nii.gz $indir/seedCorrelation/${roi}_standard.nii.gz


      #Look for the presence of deleted volumes.  ONLY create "spike" (ms) images if found, otherwise default to non-motionscrubbed images
      scrubDataCheck=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | head -1`

      if [[ $scrubDataCheck != "" ]]; then
        #Presence of scrubbed volumes

        #Split up deleted vols/spikes (from motionscrubbing), to echo out command for gnuplot
        #spikeCount=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | awk -F" " '{print NF}'`
        #xmax=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ms_ts.txt | wc -l`
        #ymin=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ms_ts.txt | sort -g | head -1 | awk '{print $1}'`
        #ymax=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ms_ts.txt | sort -g | tail -1 | awk '{print $1}'`
        
        #Summarize the time series data for report
        #echo "set term png" > $indir/gnuplotCmds
        #echo "set output \"$indir/${roi}_ms.png\"" >> $indir/gnuplotCmds
        #echo "set title \"${roi}_ms Time Series (With Deleted Volumes)\"" >> $indir/gnuplotCmds
        #echo "set xlabel \"Time Points\"" >> $indir/gnuplotCmds
        #echo "set xrange [0:$xmax]" >> $indir/gnuplotCmds
        #echo "set yrange [$ymin:$ymax]" >> $indir/gnuplotCmds

        #i=1
        #while [ $i -le $spikeCount ]
        #do
          #spikeNum=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | awk -F" "  -v cutfield=$i '{print $cutfield}'`
          #echo "set arrow $i from $spikeNum,$ymin to $spikeNum,$ymax nohead lc rgb '"green"'" >> $indir/gnuplotCmds
          #let i+=1
        #done
        #echo "plot \"$indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt\" with lines lc rgb '"blue"'" >> $indir/gnuplotCmds
        #cat $indir/gnuplotCmds | gnuplot

        #Cleanup
        #rm $indir/gnuplotCmds

        ##Creating new plots with fsl_tsplot
          #~2.2% plotting difference between actual Ymin and Ymax values (higher and lower), with fsl_tsplot
        yMax=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | sort -r | tail -1 | awk '{print ($1+($1*0.0022))}'`
        yMin=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | tail -1 | awk '{print ($1-($1*0.0022))}'`

          #Log the "scrubbed TRs"
        xNum=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | wc -l`
        count=1
        while [ $count -le $xNum ]; do
          tsPlotIn=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | head -${count} | tail -1`
          delPlotCheck=`cat $indir/${nuisancefeat}/stats/deleted_vols.txt | awk '{$1=$1}1' | grep -E '(^| )'${count}'( |$)'`
          if [ "$delPlotCheck" == "" ]; then
            delPlot=$yMin
          else
            delPlot=$yMax
          fi
          echo $delPlot >> $indir/${nuisancefeat}/stats/${roi}_censored_TRplot.txt
        let count=count+1
        done

        #Plot of normal data showing scrubbed TRs
        fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt,$indir/${nuisancefeat}/stats/${roi}_censored_TRplot.txt -t "$roi Time Series" -u 1 --start=1 -x 'Time Points (TR)' -a ",Scrubbed_TR" --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}.png

        #Plot of "scrubbed" data
        fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt -t "$roi Time Series (Scrubbed)" -u 1 --start=1 -x 'Time Points (TR)' --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}_ms.png


        echo "<br><img src=\"$indir/${roi}.png\" alt=\"${roi} seed\"><img src=\"$indir/${roi}_ms.png\" alt=\"${roi}_ms seed\"><br>" >> $indir/analysisResults.html        

      else
        #Absence of scrubbed volumes

        # Summarize the time series data for report
        #echo "set term png" > $indir/gnuplotCmds
        #echo "set output \"$indir/${roi}_ms.png\"" >> $indir/gnuplotCmds
        #echo "set title \"${roi}_ms Time Series\"" >> $indir/gnuplotCmds
        #echo "set xlabel \"Time Points\"" >> $indir/gnuplotCmds
        #echo "plot \"$indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt\" with lines" >> $indir/gnuplotCmds
        #cat $indir/gnuplotCmds | gnuplot

        #Cleanup
        #rm $indir/gnuplotCmds

        ##Creating new plots with fsl_tsplot
          #~2.2% plotting difference between actual Ymin and Ymax values (higher and lower), with fsl_tsplot
        yMax=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | sort -r | tail -1 | awk '{print ($1+($1*0.0022))}'`
        yMin=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt | tail -1 | awk '{print ($1-($1*0.0022))}'`

        fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt -t "$roi Time Series" -u 1 --start=1 -x 'Time Points (TR)' --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}.png

        echo "<br><img src=\"$indir/${roi}.png\" alt=\"$roi seed\"><br>" >> $indir/analysisResults.html        
      fi

    else
      #motionScrubFlag=2
        ##Non-motionscrubbed data
      if [ -e ${roi}.png ]; then
        rm ${roi}.png
      fi
      if [ -e ${roi}_ms.png ]; then
        rm ${roi}_ms.png
      fi

      #Check for FieldMap registration correction
      if [[ $fieldMapFlag == 1 ]]; then
        #Nonlinear warp from EPI to T1
        applywarp --in=$indir/${nuisancefeat}/stats/${roi}/cope1.nii \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_highres_zmap.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/example_func2highres_warp.nii.gz \
        --datatype=float
      else
        #Affine Transform from EPI to T1
        flirt -in $indir/${nuisancefeat}/stats/${roi}/cope1.nii \
        -ref $indir/${nuisancefeat}/reg/highres.nii.gz \
        -out $indir/seedCorrelation/${roi}_highres_zmap.nii.gz \
        -applyxfm -init $indir/${nuisancefeat}/reg/example_func2highres.mat \
        -datatype float
      fi

        #Mask out data with T1 mask (create temporary binary of skull-stripped T1)
        fslmaths $indir/${nuisancefeat}/reg/highres.nii.gz -bin $indir/${nuisancefeat}/reg/highres_mask.nii.gz -odt char
        fslmaths $indir/seedCorrelation/${roi}_highres_zmap.nii.gz -mas $indir/${nuisancefeat}/reg/highres_mask.nii.gz $indir/seedCorrelation/${roi}_highres_zmap_masked.nii.gz

      #Nonlinear warp from EPI to MNI
      applywarp --in=$indir/${nuisancefeat}/stats/${roi}/cope1.nii \
      --ref=$indir/${nuisancefeat}/reg/standard.nii.gz \
      --out=$indir/seedCorrelation/${roi}_standard_zmap.nii.gz \
      --warp=$indir/${nuisancefeat}/reg/example_func2standard_warp.nii.gz \
      --datatype=float

        #Mask out data with MNI mask
        fslmaths $indir/seedCorrelation/${roi}_standard_zmap.nii.gz -mas $FSLDIR/data/standard/MNI152_T1_2mm_brain_mask.nii.gz $indir/seedCorrelation/${roi}_standard_zmap_masked.nii.gz

        #Warp seed from MNI to T1
        applywarp --in=${roiDir}/${roi}.nii.gz \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_highres.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/standard2highres_warp.nii.gz \
        --interp=nn

      #Copy over Seed ROI  
      cp ${roiDir}/${roi}.nii.gz $indir/seedCorrelation/${roi}_standard.nii.gz

        ##Motionscrubbed data
        #Check for FieldMap registration correction
      if [[ $fieldMapFlag == 1 ]]; then
        #Nonlinear warp from EPI to T1
        applywarp --in=$indir/${nuisancefeat}/stats/${roi}_ms/cope1.nii \
        --ref=$indir/${nuisancefeat}/reg/highres.nii.gz \
        --out=$indir/seedCorrelation/${roi}_ms_highres_zmap.nii.gz \
        --warp=$indir/${nuisancefeat}/reg/example_func2highres_warp.nii.gz \
        --datatype=float
      else
        #Affine Transform from EPI to T1
        flirt -in $indir/${nuisancefeat}/stats/${roi}_ms/cope1.nii \
        -ref $indir/${nuisancefeat}/reg/highres.nii.gz \
        -out $indir/seedCorrelation/${roi}_ms_highres_zmap.nii.gz \
        -applyxfm -init $indir/${nuisancefeat}/reg/example_func2highres.mat \
        -datatype float
      fi

        #Mask out data with T1 mask (remove temporary binary of skull-stripped T1)
        fslmaths $indir/seedCorrelation/${roi}_ms_highres_zmap.nii.gz -mas $indir/${nuisancefeat}/reg/highres_mask.nii.gz $indir/seedCorrelation/${roi}_ms_highres_zmap_masked.nii.gz
        rm $indir/${nuisancefeat}/reg/highres_mask.nii.gz

      #Nonlinear warp from EPI to MNI
      applywarp --in=$indir/${nuisancefeat}/stats/${roi}_ms/cope1.nii \
      --ref=$indir/${nuisancefeat}/reg/standard.nii.gz \
      --out=$indir/seedCorrelation/${roi}_ms_standard_zmap.nii.gz \
      --warp=$indir/${nuisancefeat}/reg/example_func2standard_warp.nii.gz \
      --datatype=float

        #Mask out data with MNI mask
        fslmaths $indir/seedCorrelation/${roi}_ms_standard_zmap.nii.gz -mas $FSLDIR/data/standard/MNI152_T1_2mm_brain_mask.nii.gz $indir/seedCorrelation/${roi}_ms_standard_zmap_masked.nii.gz


      #Look for the presence of deleted volumes.  ONLY create "spike" (ms) images if found, otherwise default to non-motionscrubbed images
      scrubDataCheck=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | head -1`

      if [[ $scrubDataCheck != "" ]]; then
        #Presence of scrubbed volumes

        #Split up deleted vols/spikes (from motionscrubbing), to echo out command for gnuplot
        #spikeCount=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | awk -F" " '{print NF}'`
        #xmax=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ts.txt | wc -l`
        #ymin=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ts.txt | sort -g | head -1 | awk '{print $1}'`
        #ymax=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ts.txt | sort -g | tail -1 | awk '{print $1}'`
        
        #Summarize the time series data for report
        #echo "set term png" > $indir/gnuplotCmds
        #echo "set output \"$indir/${roi}_ms.png\"" >> $indir/gnuplotCmds
        #echo "set title \"${roi}_ms Time Series (With Deleted Volumes)\"" >> $indir/gnuplotCmds
        #echo "set xlabel \"Time Points\"" >> $indir/gnuplotCmds
        #echo "set xrange [0:$xmax]" >> $indir/gnuplotCmds
        #echo "set yrange [$ymin:$ymax]" >> $indir/gnuplotCmds

        #i=1
        #while [ $i -le $spikeCount ]
        #do
          #spikeNum=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | awk -F" "  -v cutfield=$i '{print $cutfield}'`
          #echo "set arrow $i from $spikeNum,$ymin to $spikeNum,$ymax nohead lc rgb '"green"'" >> $indir/gnuplotCmds
          #let i+=1
        #done
        #echo "plot \"$indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt\" with lines lc rgb '"blue"'" >> $indir/gnuplotCmds
        #cat $indir/gnuplotCmds | gnuplot

        #Cleanup
        #rm $indir/gnuplotCmds 

        ##Creating new plots with fsl_tsplot
          #~2.2% plotting difference between actual Ymin and Ymax values (higher and lower), with fsl_tsplot
        yMax=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | sort -r | tail -1 | awk '{print ($1+($1*0.0022))}'`
        yMin=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | tail -1 | awk '{print ($1-($1*0.0022))}'`

          #Log the "scrubbed TRs"
        xNum=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | wc -l`
        count=1
        while [ $count -le $xNum ]; do
          tsPlotIn=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | head -${count} | tail -1`
          delPlotCheck=`cat $indir/${nuisancefeat}/stats/deleted_vols.txt | awk '{$1=$1}1' | grep -E '(^| )'${count}'( |$)'`
          if [ "$delPlotCheck" == "" ]; then
            delPlot=$yMin
          else
            delPlot=$yMax
          fi
          echo $delPlot >> $indir/${nuisancefeat}/stats/${roi}_censored_TRplot.txt
        let count=count+1
        done

        #Plot of normal data showing scrubbed TRs
        fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt,$indir/${nuisancefeat}/stats/${roi}_censored_TRplot.txt -t "$roi Time Series" -u 1 --start=1 -x 'Time Points (TR)' -a ",Scrubbed_TR" --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}.png

        #Plot of "scrubbed" data
        fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ms_ts.txt -t "$roi Time Series (Scrubbed)" -u 1 --start=1 -x 'Time Points (TR)' --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}_ms.png


        echo "<br><img src=\"$indir/${roi}.png\" alt=\"${roi} seed\"><img src=\"$indir/${roi}_ms.png\" alt=\"${roi}_ms seed\"><br>" >> $indir/analysisResults.html

      else
        #No scrubbed TRs

        #Split up deleted vols/spikes (from motionscrubbing), to echo out command for gnuplot
        #spikeCount=`cat $indir/$nuisancefeat/stats/deleted_vols.txt | awk -F" " '{print NF}'`
        #xmax=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ts.txt | wc -l`
        #ymin=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ts.txt | sort -g | head -1 | awk '{print $1}'`
        #ymax=`cat $indir/$nuisancefeat/stats/${roi}_residvol_ts.txt | sort -g | tail -1 | awk '{print $1}'`

        # Summarize the time series data for report
        #echo "set term png" > $indir/gnuplotCmds
        #echo "set output \"$indir/${roi}.png\"" >> $indir/gnuplotCmds
        #echo "set title \"$roi Time Series\"" >> $indir/gnuplotCmds
        #echo "set xlabel \"Time Points\"" >> $indir/gnuplotCmds
        #echo "plot \"$indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt\" with lines" >> $indir/gnuplotCmds
        #cat $indir/gnuplotCmds | gnuplot

        #Cleanup
        #rm $indir/gnuplotCmds

        ##Creating new plots with fsl_tsplot
          #~2.2% plotting difference between actual Ymin and Ymax values (higher and lower), with fsl_tsplot
        yMax=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | sort -r | tail -1 | awk '{print ($1+($1*0.0022))}'`
        yMin=`cat $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt | tail -1 | awk '{print ($1-($1*0.0022))}'`

        fsl_tsplot -i $indir/${nuisancefeat}/stats/${roi}_residvol_ts.txt -t "$roi Time Series" -u 1 --start=1 -x 'Time Points (TR)' --ymin=$yMin --ymax=$yMax -w 800 -h 300 -o $indir/${roi}.png

        echo "<br><img src=\"$indir/${roi}.png\" alt=\"$roi seed\"><br>" >> $indir/analysisResults.html             
      fi
    fi     
  done
fi

#################################


echo "$0 Complete"
echo "Please make sure that the ROI folders were created in the nuisancereg.feat/stats/ folder."
echo "If resultant warped seeds (to MNI) were too small, they were NOT processed.  Check nuisancereg.feat/stats/seedsTooSmall for exclusions."
echo "If motionscrubbing was set to 1 or 2, make sure that motionscrubbed data was created."
echo "OCTAVE/Matlab wouldn't give an error even if this step was not successfully done."
echo ""
echo ""







