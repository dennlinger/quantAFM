
if( strcmp(getenv('OS'),'Windows_NT'))
    addpath(genpath('..\denoised_imgs'));
    currentImageDir = '..\denoised_imgs\all\*.tif';
    
else
    addpath(genpath('../denoised_imgs'));
    currentImageDir = '../denoised_imgs/handausgewertet/';
end


running = gcp('nocreate');
if running == 0;
    parpool('local');
end

imageFolderObj = dir(currentImageDir);
imageCount = size(dir(currentImageDir),1);
imageList = cell(1,imageCount);

threshAlgo = 'otsu';
%maxentropy - no good
%intermodes - better than maxentropy, but still bad
%minerror - no good
threshAlgo1 = 'otsu'; 

manThresh = 95;
thresh1 =  zeros(1,imageCount);
thresh2 =  zeros(1,imageCount);
% median and sigma over ALL thresholds of ALL images
medianTheshold = 0.4353;
sigmaThreshold = 0.0124;

par = 0; %bool wether to use multiple cores or not
gpu = 0; %bool wether to use gpu or not

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
    
    
    imageList{index}.preprocImg = lowPassFilter(imageList{index}.rawImage);
    imageList{index}.preprocImg = medfilt2(imageList{index}.preprocImg,[3 3]);
    imageList{index}.background = imopen(imageList{index}.preprocImg, strel('disk',15));
    imageList{index}.preprocImg(imageList{index}.preprocImg< manThresh) = manThresh;
    %% Replace image artifacts
    % Here, an initial bw image is generated using a global thresholding
    % algorithm. In this phase of the image processing, the threshold's
    % accuracy is not so important. The primary goal is to identify
    % image artifacts that
    % -  have a too high intensity and
    % -  are smaller than 150 px or larger than 900 px
    % and replace their pixel values with a value that is below an optimal
    % threshold so that they will be filtered out later on.
    
    thresh = threshold(threshAlgo, imageList{index}.preprocImg);
    imageList{index}.thresh = thresh;
    thresh1(index) = thresh;
    imageList{index}.bwImage = im2bw(imageList{index}.preprocImg, thresh);
%     imageList{index}.bwImage = bwareafilt(imageList{index}.bwImage, [100,900]);

    % remove objects from bwImage with pixelsize in [150, 900]
    
    imageList{index}.bwFilteredImage = ...
        imageList{index}.bwImage - bwareafilt(imageList{index}.bwImage, [0,900]);
    % generate complement image that is 1 where there are NO artifacts and
    % 0 otherwise
    
    complementImage = imcomplement(imageList{index}.bwFilteredImage);
    
    % generate new uint8 image by
    % - setting the intensity of all previously identified artifacts to 80%
    %   of the initially calculated threshold, and
    % - combining this with those pixels from the preprocessed image that
    %   are no artifacts
    
    imageList{index}.filteredImage = ...
        uint8(imageList{index}.preprocImg) .* uint8(complementImage);
    imageList{index}.filteredImage(imageList{index}.filteredImage< manThresh) = manThresh;
    
    % use this cleaned image to calculate a more accurate threshold and
    % compute a bw image from that contains mostly DNA fragments/nucleosomes.
    
    t = threshold(threshAlgo1 , imageList{index}.filteredImage);
    thresh2(index)= t;
    if ((t < medianTheshold-sigmaThreshold) || (t > medianTheshold+sigmaThreshold))
        t = medianTheshold;
        
    end
    imageList{index}.bwImgThickDna = im2bw(imageList{index}.filteredImage, t);
    
    % finally, remove any objects that might not be in the expected size
    % range of [100, 900]
    imageList{index}.bwImgThickDna = bwareafilt(imageList{index}.bwImgThickDna, [150,900]);
    
    %find circles, nuklei, centers, and radi
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

    %     Go through all objects within the connected Components and create DNA
    %     Objects for them. DNABound if it is connected to a Nukleii and
    %     DNAFree if not
    for dnaIndex = 1:dnaCount
        %         Check if there are any Nukleii detected on the bwThinnedDNAImg
        if ~isempty(centers)
            %             Check whether any of the Nukleii are attached to the current
            %             DNA strand(connected Component)
            imageList{index}.contains = uint8(ismember(imageList{index}.indexcenters,...
                imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}));     
        end
%         Calculate Bounding Box for DNA strand.
        bBox = imageList{index}.boundingBoxDna(dnaIndex);

%       create small detail image of current DNA fragment using the
%       calculated bounding box
        detail_thickDna = imageList{index}.bwImgThickDna(...
            round(bBox.BoundingBox(2)): floor(bBox.BoundingBox(2)+bBox.BoundingBox(4)),...
            round(bBox.BoundingBox(1)): floor(bBox.BoundingBox(1)+bBox.BoundingBox(3)));
        bBox.BoundingBox(1) = round(bBox.BoundingBox(1));
        bBox.BoundingBox(2) = round(bBox.BoundingBox(2));
        %         Check if there was a Nukleii found that is attached to this
        %         connectedComponent
        if sum(imageList{index}.contains)~= 0
            %             find all Nukleii that are attached to this connected
            %             Component
            nukleoIndecies = find(imageList{index}.contains);
            %             create a Nukleii Object for all Nukleii found
            nukleos = cell(1,numel(nukleoIndecies));
            
            %             Set all numbers of current DNA to all nukleos attached
            imageList{index}.attachedDNA(nukleoIndecies) = dnaIndex;
            for i=1:numel(nukleoIndecies)
                %                 Save all Nukleii found in a Cell
                nukleos{i} = nukleo(imageList{index}.centers(nukleoIndecies(i),:), ...
                    imageList{index}.radii(nukleoIndecies(i),:), dnaIndex, ...
                    imageList{index}.centers(nukleoIndecies(i),:) - bBox.BoundingBox(1:2));
            end
            
%             create DNABound Object for every Object detected in the Image
%             Set Type,ConnectedComponents, position and subImage from
%             Bounding box
             imageList{index}.dnaList{dnaIndex} = DnaBound(...
                 imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}, ...
                 detail_thickDna, ...
                 imageList{index}.region(dnaIndex,:),...
                 1,...
                 nukleos);
            %%%%TODO%%%%
            % Here, we could check the length of the dnaObject's
            % pixelIdxList' length. If it is below a certain value or
            % above, it is likely not a DNA fragment, so we should discard
            % it and not compute anything for it.
            %%%%CURRENTLY%%%%%%
            % Currently, each DNA object has an isValid flag. This is set
            % if after length determination the DNA backbone does not fit
            % the generally specified DNA length criteria
            %imageList{index}.dnaList{dnaIndex} = getDNALength(imageList{index}.dnaList{dnaIndex});
            imageList{index}.dnaList{dnaIndex} = determineDnaLength2(imageList{index}.dnaList{dnaIndex});
            %          Calculate angle between the Nukleii and the arms(the DNA Arms
            [ imageList{index}.dnaList{dnaIndex}.angle1, ...
                imageList{index}.dnaList{dnaIndex}.angle2, ...
                intersecting_pixels] = ...
            measure_angle(imageList{index}.dnaList{dnaIndex});
        else
            %             When no Nukleii is attached, Create DNAFree Object and set
            %             Type, ConnectedComponents and position 
            imageList{index}.dnaList{dnaIndex} = DnaFree(...
                imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}, ...
                detail_thickDna,...
                imageList{index}.region(dnaIndex,:));
            %imageList{index}.dnaList{dnaIndex} = getDNALength(imageList{index}.dnaList{dnaIndex});
            imageList{index}.dnaList{dnaIndex} = determineDnaLength2(imageList{index}.dnaList{dnaIndex});            

        end
        %         Set the dnaIndex as Number for the DNA strand object
        imageList{index}.dnaList{dnaIndex}.number = dnaIndex;
        imageList{index}.dnaList{dnaIndex}.bBox = bBox;
    end
    
    if( strcmp(getenv('OS'),'Windows_NT'))
        
        imwrite(imageList{index}.preprocImg , ['..\pictures\preprocImg\' 'preproc' imageFolderObj(index).name ]);
        imwrite(imageList{index}.background , ['..\pictures\background\' 'bckground' imageFolderObj(index).name ]);
        imwrite(imageList{index}.bwImage , ['..\pictures\bwImage\' 'bw' imageFolderObj(index).name ]);
        imwrite(imageList{index}.bwFilteredImage , ['..\pictures\bwFilteredImage\' 'bwFiltered' imageFolderObj(index).name ]);
        imwrite(imageList{index}.filteredImage , ['..\pictures\filteredImage\' 'filtered' imageFolderObj(index).name ]);
        imwrite(imageList{index}.bwImgThickDna , ['..\pictures\bwImgThickDna\' 'bwThickDna' imageFolderObj(index).name ]);
        %     imwrite(imageList{index}.bwImgDen , ['..\pictures\bwImgDen\' 'bwImgDen' imageFolderObj(index).name ]);
%         imwrite(imageList{index}.bwImgThinnedDna , ['..\pictures\bwImgThinnedDna\' 'thinnedDna' imageFolderObj(index).name ]);
        
    else
         imwrite(imageList{index}.preprocImg , ['../pictures/preprocImg/' 'me_preproc' imageFolderObj(index).name ]);
         imwrite(imageList{index}.background , ['../pictures/background/' 'me_bckground' imageFolderObj(index).name ]);
         imwrite(imageList{index}.bwImage , ['../pictures/bwImage/' 'me_bw' imageFolderObj(index).name ]);
         imwrite(imageList{index}.bwFilteredImage , ['../pictures/bwFilteredImage/' 'me_bwFiltered' imageFolderObj(index).name ]);
         imwrite(imageList{index}.filteredImage , ['../pictures/filteredImage/' 'me_filtered' imageFolderObj(index).name ]);
         imwrite(imageList{index}.bwImgThickDna , ['../pictures/bwImgThickDna/' 'me_bwThickDna' imageFolderObj(index).name ]);
%         imwrite(imageList{index}.bwImgDen , ['..\pictures\bwImgDen\' 'bwImgDen' imageFolderObj(index).name ]);
%          imwrite(imageList{index}.bwImgThinnedDna , ['../pictures/bwImgThinnedDna/' 'me_thinnedDna' imageFolderObj(index).name ]);
%          imwrite(imfuse(imageList{index}.rawImage , imageList{index}.bwImgThinnedDna), ['../pictures/overlays_thin/' 'overlay_' imageFolderObj(index).name ]);
         imwrite(imfuse(imageList{index}.rawImage , imageList{index}.bwImgThickDna), ['../pictures/overlays_thick/' 'overlay__' imageFolderObj(index).name ]);
    end
%     showImage(imageList{index});
%     w = waitforbuttonpress;
%     close;
%     writeToCsvFile([imageFolderObj(index).name 'fast_ChrLen.csv'], imageList{index});
end
