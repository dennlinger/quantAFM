config;
global PIXELLENGTH PIXELPERNM MINLENGTH_FREE MAXLENGTH_FREE MINLENGTH_BOUND ...
        MAXLENGTH_BOUND MINRADIUS MAXRADIUS RECOVERBACKBONE REALVALUE ...
        EXPORTREAL EXPORTONLYVALID SENSITIVITY EDGETHRESHOLD ANGLERADIUS ...
        AVERAGELENGTH ANGLETHRESHOLD GROWING;
PIXELLENGTH = (scansize * 1000) / xResolution;
PIXELPERNM = 1 / PIXELLENGTH;

MINLENGTH_FREE = minLength_free * PIXELPERNM;
MAXLENGTH_FREE = maxLength_free * PIXELPERNM;

MINLENGTH_BOUND = minLength_bound * PIXELPERNM;
MAXLENGTH_BOUND = maxLength_bound * PIXELPERNM;

MINRADIUS = floor(minRadius*PIXELPERNM);
MAXRADIUS = ceil(maxRadius*PIXELPERNM);

SENSITIVITY = sensitivity;
EDGETHRESHOLD = edgeThreshold;

ANGLERADIUS = angleRadius;
ANGLETHRESHOLD = angleThreshold;
GROWING = growing;

RECOVERBACKBONE = recoverBackbone;
AVERAGELENGTH = averageLength;

REALVALUE = realValue;

EXPORTREAL = exportReal;
EXPORTONLYVALID = exportOnlyValid;

addpath(genpath(workingDir));
% Not sure what this is used for. Probably can be removed.
addpath(genpath('LengthEstimation'));

if (px2nm_output == 1)
    disp(['A single pixel has length ' num2str(PIXELLENGTH) ' nm.']);
end

imageFolderObj = dir(currentImageDir);
% exclude potentially hazardous files from the current folder.
imageFolderObj = imageFolderObj(~ismember({imageFolderObj.name}, {'.', '..', '.DS_Store'}));
imageCount = size(imageFolderObj,1);
imageList = cell(1,imageCount);

manThresh = backgroundThreshold;
thresh1 =  zeros(1,imageCount);
thresh2 =  zeros(1,imageCount);
% median and sigma over ALL thresholds of ALL images
medianTheshold = 0.4353;
sigmaThreshold = 0.0124;

if (minSize == -1)
    minSize = 0.03*xResolution;
end
if (maxSize == -1)
    maxSize = 0.85*xResolution;
end

par = parallel; %bool wether to use multiple cores or not
% gpu = gpu; %bool wether to use gpu or not

for index = 1:imageCount
    %% this is required for Archlinux
     if or( strcmp(imageFolderObj(index).name , '.'), strcmp(imageFolderObj(index).name, '..') )
         continue
     end
    
    %[image,colorMap] = imread(strcat(currentImageDir, imageFolderObj(index).name));
    %% until here

    
    [image,colorMap] = imread(imageFolderObj(index).name);
    imageList{index} = Image(image, colorMap);
    
    %% Call OpenCV function to denoise the image before further processing.
    % Results in more DNA fragments to be recognized, but also in loss of
    % some that were recognized before
    % Also increases processing time severely (about 12 sec per image),
    % but might be worth it.
    % The file denoising.mexa64 was generated by calling:
    %       mexOpenCV ocvDenoise.cpp
    % ATTENTION: probably requires the package from this link to be installed
    %   http://de.mathworks.com/matlabcentral/fileexchange/47953-computer-vision-system-toolbox-opencv-interface
    % ATTENTION: might require OpenCV to be installed (don't know that).
    
    % In case we want to include this function in our preprocessing step,
    % we can delete most of the following code (and also some variables in
    % Image.m. I only included it so that
    % we can see the differences in the outcome between both methods (with
    % and without this function).
    
    

    %% Initial preprocessing step.
    % The image is lowpass filtered on its frequency domain, then median
    % filtered. Afterwards, its background is auto-calculated and
    % substracted. This image will be the basis for further processing.
    
    if(gpu && medfilter)
        gpuRawImage = gpuArray(imageList{index}.rawImage);
        gpuRawImage = medfilt2(gpuRawImage, [3,3]);
        imageList{index}.preprocImg = gather(gpuRawImage);
    elseif(medfilter)
        imageList{index}.preprocImg = medfilt2(imageList{index}.rawImage,[3 3]);
    end
    if(medfilter && lowpass)
        imageList{index}.preprocImg = lowPassFilter(imageList{index}.preprocImg);
    elseif(lowpass)
        imageList{index}.preprocImg = lowPassFilter(imageList{index}.rawImage);
    end
    
    if (~(medfilter && lowpass))
        imageList{index}.preprocImg = imageList{index}.rawImage;
    end
    
    imageList{index}.background = imopen(imageList{index}.preprocImg, strel('disk',15));
    imageList{index}.preprocImg(imageList{index}.preprocImg< manThresh) = manThresh;
    %% Replace image artifacts
    % Here, an initial bw image is generated using a global thresholding
    % algorithm. In this phase of the image processing, the threshold's
    % accuracy is not so important. The primary goal is to identify
    % image artifacts that
    % -  have a too high intensity and
    % -  are smaller than minSize px or larger than maxSize px
    % and replace their pixel values with a value that is below an optimal
    % threshold so that they will be filtered out later on.
    
    thresh = threshold(threshAlgorithm1, imageList{index}.preprocImg);
    imageList{index}.thresh = thresh;
    thresh1(index) = thresh;
end


if(setMeanThreshold ~= 0)
    medianThreshold = median(thresh1);
    sigmaThreshold = std(thresh1);
end

for index = 1:imageCount
    if or( strcmp(imageFolderObj(index).name , '.'), strcmp(imageFolderObj(index).name, '..') )
        continue
    end
    imageList{index}.bwImage = im2bw(imageList{index}.preprocImg, imageList{index}.thresh);
%     imageList{index}.bwImage = bwareafilt(imageList{index}.bwImage, [minSize,maxSize]);

    % remove objects from bwImage with pixelsize in [0, maxSize]
    % this is only the filtering step, so the lower boundary may be
    % optional. For different results, this could be enabled, too.
    imageList{index}.bwFilteredImage = ...
        imageList{index}.bwImage - bwareafilt(imageList{index}.bwImage, [0,maxSize]);
    
    % generate complement image that is 1 where there are NO artifacts and
    % 0 otherwise.
    complementImage = imcomplement(imageList{index}.bwFilteredImage);
    
    % generate new uint8 image by
    % - setting the intensity of all previously identified artifacts to 80%
    %   of the initially calculated threshold, and
    % - combining this with those pixels from the preprocessed image that
    %   are no artifacts
    
    imageList{index}.filteredImage = ...
        uint8(imageList{index}.preprocImg) .* uint8(complementImage);
    imageList{index}.filteredImage(imageList{index}.filteredImage< manThresh) = manThresh;
    

    if (binarizer == 1)
        % directly calculate new images. Doesn't require threshold at all.
        imageList{index}.bwImgThickDna = imbinarize(imageList{index}.filteredImage); 
        
    else
        % use this cleaned image to calculate a more accurate threshold and
        % compute a bw image from that contains mostly DNA fragments/nucleosomes.
        t = threshold(threshAlgorithm2 , imageList{index}.filteredImage);
        thresh2(index)= t;
        if ((t < medianTheshold-sigmaThreshold) || (t > medianTheshold+sigmaThreshold))
            t = medianTheshold;
        end
        imageList{index}.bwImgThickDna = im2bw(imageList{index}.filteredImage, t);
    end
    
    % finally, remove any objects that might not be in the expected size
    % range of [minSize, maxSize]
    imageList{index}.bwImgThickDna = bwareafilt(imageList{index}.bwImgThickDna, [minSize,maxSize]);
    
    %find circles, nuklei, centers, and radii
    [ imageList{index}.centers,imageList{index}.radii] = ...
        findNukleii(imageList{index}.bwImgThickDna, imageList{index}.preprocImg);
    
    %get properties of all objects on the ThickDnaBwImage
    imageList{index}.connectedThickDna = bwconncomp(imageList{index}.bwImgThickDna);
    region =  regionprops(imageList{index}.connectedThickDna, 'Centroid');
    imageList{index}.boundingBoxDna = regionprops(imageList{index}.connectedThickDna, 'BoundingBox');
    %     Concat the all Centers of mass of the objects to a 2-1 Cell Array
    %     with x and y values.
    imageList{index}.region = cat(1,region.Centroid);
    
    dnaCount = imageList{index}.connectedThickDna.NumObjects;
    
    imageList{index}.dnaList =  cell(1,dnaCount);
    % calculate centers in int coord.
    centers = round(imageList{index}.centers);
    imageList{index}.centers = round(imageList{index}.centers);
    %     set size of attachedDNA array
    imageList{index}.attachedDNA = zeros(size(centers,1),1);
    
    % convert centers from Point to index
    imageList{index}.imgSize =  size(imageList{index}.bwImgThickDna);
    [m,n] = size(imageList{index}.bwImgThickDna);
    if ~isempty(centers)
        imageList{index}.indexcenters = (centers(:,1)-1)*m + centers(:,2) ;
    end
    % Go through all objects within the connected Components and create DNA
    % Objects for them. DNABound if it is connected to a Nukleii and
    % DNAFree if not
    for dnaIndex = 1:dnaCount
        % Check if there are any Nukleii detected on the bwThinnedDNAImg
        if ~isempty(centers)
            % Check whether any of the Nukleii are attached to the current
            % DNA strand(connected Component)
            imageList{index}.contains = uint8(ismember(imageList{index}.indexcenters,...
                imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}));     
        end
        % Calculate Bounding Box for DNA strand.
        bBox = imageList{index}.boundingBoxDna(dnaIndex);

        % create small detail image of current DNA fragment using the
        % calculated bounding box
        detail_thickDna = imageList{index}.bwImgThickDna(...
            round(bBox.BoundingBox(2)): floor(bBox.BoundingBox(2)+bBox.BoundingBox(4)),...
            round(bBox.BoundingBox(1)): floor(bBox.BoundingBox(1)+bBox.BoundingBox(3)));
        
        detail_rawDna = imageList{index}.filteredImage(...
            round(bBox.BoundingBox(2)): floor(bBox.BoundingBox(2)+bBox.BoundingBox(4)),...
            round(bBox.BoundingBox(1)): floor(bBox.BoundingBox(1)+bBox.BoundingBox(3)));
        bBox.BoundingBox(1) = round(bBox.BoundingBox(1));
        bBox.BoundingBox(2) = round(bBox.BoundingBox(2));
        % Check if there was a Nukleii found that is attached to this
        % connectedComponent
        if sum(imageList{index}.contains)~= 0
            % find all Nukleii that are attached to this connected
            % Component
            nukleoIndecies = find(imageList{index}.contains);
            % create a Nukleii Object for all Nukleii found
            nukleos = cell(1,numel(nukleoIndecies));
            
            % Set all numbers of current DNA to all nukleos attached
            imageList{index}.attachedDNA(nukleoIndecies) = dnaIndex;
            for i=1:numel(nukleoIndecies)
                % Save all Nukleii found in a Cell
                nukleos{i} = nukleo(imageList{index}.centers(nukleoIndecies(i),:), ...
                    imageList{index}.radii(nukleoIndecies(i),:), dnaIndex, ...
                    imageList{index}.centers(nukleoIndecies(i),:) - bBox.BoundingBox(1:2));
            end
            
            % create DNABound Object for every Object detected in the Image
            % Set Type,ConnectedComponents, position and subImage from
            % Bounding box
            imageList{index}.dnaList{dnaIndex} = DnaBound(...
                imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}, ...
                detail_thickDna, ...
                detail_rawDna, ...
                imageList{index}.region(dnaIndex,:),...
                1,...
                nukleos);
            %%%%TODO%%%%
            % Here, we could check the length of the dnaObject's
            % pixelIdxList' length. If it is below a certain value or
            % above, it is likely not a DNA fragment, so we should discard
            % it and not compute anything for it.
            %%%%CURRENT IMPLEMENTATION%%%%%%
            % Currently, each DNA object has an isValid flag. This is set
            % if after length determination the DNA backbone does not fit
            % the generally specified DNA length criteria
            imageList{index}.dnaList{dnaIndex} = determineDnaLength2(imageList{index}.dnaList{dnaIndex}, true);
            % Calculate angle between the Nukleii and the arms
            % (the DNA Arms)
%             index
            [ imageList{index}.dnaList{dnaIndex}.angle1, ...
                imageList{index}.dnaList{dnaIndex}.angle2] = ...
            measure_angle(imageList{index}.dnaList{dnaIndex});
        else
            % When no Nukleii is attached, Create DNAFree Object and set
            % Type, ConnectedComponents and position 
            imageList{index}.dnaList{dnaIndex} = DnaFree(...
                imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}, ...
                detail_thickDna,...
                detail_rawDna, ...
                imageList{index}.region(dnaIndex,:));
            
            imageList{index}.dnaList{dnaIndex} = determineDnaLength2(imageList{index}.dnaList{dnaIndex}, false);

        end
        % Set the dnaIndex as Number for the DNA strand object
        imageList{index}.dnaList{dnaIndex}.number = dnaIndex;
        imageList{index}.dnaList{dnaIndex}.bBox = bBox;
    end
    
    % create bwImgThinnedDna from all DnaObjects
    % this can be critical for overlapping sections, since the local image
    % is blacked out in said overlapping area, so it might overwrite later
    % additions. Thus, a simple addition is performed, instead of an
    % assignment to this area. Still, some risk is involved, since the
    % value may increase beyond one (renormalized in the end).
    imageList{index}.bwImgThinnedRemoved = zeros(imageList{index}.imgSize);
    for dna = 1:length(imageList{index}.dnaList)
        % this also only continues for DNAs that have a single (valid)
        % strand. It is shown regardless of the processing results
        % afterwards, yet it has to yield some result for the de-branching
        % process (after the thinning already occured).
        if (~isempty(imageList{index}.dnaList{dna}.bwImageThinnedRemoved))
            thisBB = imageList{index}.dnaList{dna}.bBox.BoundingBox;
            imageList{index}.bwImgThinnedRemoved(thisBB(2):thisBB(2)+thisBB(4)-1,thisBB(1):thisBB(1)+thisBB(3)-1) = ...
                imageList{index}.bwImgThinnedRemoved(thisBB(2):thisBB(2)+thisBB(4)-1,thisBB(1):thisBB(1)+thisBB(3)-1) + ...
                imageList{index}.dnaList{dna}.bwImageThinnedRemoved;
        end
    end
    imageList{index}.bwImgThinnedRemoved = logical(imageList{index}.bwImgThinnedRemoved);
    
    % select the subset that consists only of the valid ones
    if (purgeInvalid)
        imageList{index}.purged = [];
        for i=1:length(imageList{index}.dnaList)
            if (imageList{index}.dnaList{i}.isValid)
               imageList{index}.purged = [imageList{index}.purged, i]; 
            end
        end
    end
    
    % Check whether folder structure already exists:
    createFolder(outputDir);
    createFolder(fullfile(outputDir, 'preprocImg'));
    createFolder(fullfile(outputDir, 'background'));
    createFolder(fullfile(outputDir, 'bwImage'));
    createFolder(fullfile(outputDir, 'bwFilteredImage'));
    createFolder(fullfile(outputDir, 'filteredImage'));
    createFolder(fullfile(outputDir, 'bwImgThickDna'));
    createFolder(fullfile(outputDir, 'bwImgThinnedDna'));
    createFolder(fullfile(outputDir, 'overlays_thick'));
    createFolder(fullfile(outputDir, 'fused_images'));
        
    % Write respective images to files
    imwrite(imageList{index}.preprocImg , ...
            fullfile(outputDir, 'preprocImg', ['preproc' imageFolderObj(index).name ]));
    imwrite(imageList{index}.background , ...
            fullfile(outputDir, 'background', ['background' imageFolderObj(index).name ]));
    imwrite(imageList{index}.bwImage , ...
            fullfile(outputDir, 'bwImage', ['bw' imageFolderObj(index).name ]));
    imwrite(imageList{index}.bwFilteredImage , ...
            fullfile(outputDir, 'bwFilteredImage', ['bwFiltered' imageFolderObj(index).name ]));
    imwrite(imageList{index}.filteredImage , ...
            fullfile(outputDir, 'filteredImage', ['filtered' imageFolderObj(index).name ]));
    imwrite(imageList{index}.bwImgThickDna , ...
            fullfile(outputDir, 'bwImgThickDna', ['bwThickDna' imageFolderObj(index).name ]));
    imwrite(imageList{index}.bwImgThinnedRemoved , ...
            fullfile(outputDir, 'bwImgThinnedDna', ['thinnedDnaRemoved' imageFolderObj(index).name ]));
    imwrite(imfuse(imageList{index}.rawImage , imageList{index}.bwImgThickDna), ...
            fullfile(outputDir, 'overlays_thick', ['overlay_' imageFolderObj(index).name ]));
    showImage(imageList{index}, ...
              fullfile(outputDir, 'overlays_thick', ['overlays_' imageFolderObj(index).name ]), ...
              showBB, showThin, purgeInvalid);
    fusedImages(imageList{index}, imageFolderObj(index).name, outputDir);
    
    %% write output: image with detected objects, csv file with results for each object
   output_filename = fullfile(csvDir, [imageFolderObj(index).name '.csv']);
    writeToCsvFile(output_filename, imageList{index}, purgeInvalid, verbose);
    
    
    %% if enabled, write the exported pixel values of each DNA strand
    if (exportPixels == 1)
        export_filename = fullfile(exportDirLinux, num2str(index, '%03i'));
        export_pixels(export_filename, imageList{index});
    end
    
end


