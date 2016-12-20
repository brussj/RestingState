% It is matlab script
addpath('/Volumes/VossLab/Universal_Software/RestingState2014a')
statsScripts=['/Volumes/VossLab/Universal_Software/RestingState2014a','/Octave/nifti'];
addpath(statsScripts)
fid=fopen('/Users/VossLabMount/Projects/Bilingualism_DisEGV/sub192_1/rsOut/func/seeds.txt');
roiList=textscan(fid,'%s');
fclose(fid);

funcvoldim=[  ];
doFisherZ=1;
motion_scrub=1;
input='res4d_normandscaled_motionscrubbed.nii';

firstlevelseeding_parallel('/Users/VossLabMount/Projects/Bilingualism_DisEGV/sub192_1/rsOut/func',roiList,'nuisancereg.feat',funcvoldim,input,motion_scrub,doFisherZ)
quit
  