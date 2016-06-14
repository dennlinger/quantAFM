
if( strcmp(getenv('OS'),'Windows_NT'))
    addpath(genpath('..\pictures'));    
    currentImageDir = '..\pictures\p_Wildtyp\*.tif';
    
else
    addpath(genpath('../pictures'));
    currentImageDir = '../pictures/p_Wildtyp/';
end
        
    
cpuCores = 4;

running = gcp('nocreate');
if running == 0;
    parpool('local', cpuCores);
end

imageFolderObj = dir(currentImageDir);
imageCount = size(dir(currentImageDir),1);
imageList = cell(1,imageCount);
threshAlgo = 'moments';
threshAlgo1 = 'moments';



parfor index = 1:imageCount
    %% this is required for Archlinux
    if or( strcmp(imageFolderObj(index).name , '.'), strcmp(imageFolderObj(index).name, '..') )
        continue
    end
%    [image,colorMap] = imread(strcat(currentImageDir, imageFolderObj(index).name));
    %% until here
    
%    imageList{index}.metaImage = imfinfo(imageFolderObj(index).name);
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
    
    
%     imageList{index}.denoisedImg = ocvDenoise(imageList{index}.rawImage);
%     imageList{index}.denoisedImg =imageList{index}.rawImage;
%     imageList{index}.denoisedImg = lowPassFilter(imageList{index}.denoisedImg);
%     imageList{index}.denoisedImg = medfilt2(imageList{index}.denoisedImg,[3 3]);
%     imageList{index}.background = imopen(imageList{index}.denoisedImg, strel('disk',15));
%     imageList{index}.denoisedImg = imageList{index}.denoisedImg - imageList{index}.background;
%     thresh = threshold(threshAlgo, imageList{index}.denoisedImg);
%     imageList{index}.bwImgDen = im2bw(imageList{index}.denoisedImg,thresh);
%     bwImageremoved = bwareafilt(imageList{index}.bwImgDen, [150,900]);
%     bwImageremoved = imageList{index}.bwImgDen - bwImageremoved;
%     complement = imcomplement(bwImageremoved);
%     cleanImage = uint8(imageList{index}.denoisedImg) .* uint8(complement);
%     t = threshold(threshAlgo1 , cleanImage);
%     imageList{index}.bwImgDen = im2bw(cleanImage,t);
%     imageList{index}.bwImgDen = bwareafilt(imageList{index}.bwImgDen, [0, 900]);
%     imageList{index}.bwImgDenThinned = bwmorph(imageList{index}.bwImgDen,'thin',Inf);
    
    %% Initial preprocessing step.
    % The image is lowpass filtered on its frequency domain, then median 
    % filtered. Afterwards, its background is auto-calculated and 
    % substracted. This image will be the basis for further processing.
    
    
    imageList{index}.preprocImg = lowPassFilter(imageList{index}.rawImage);
    imageList{index}.preprocImg = medfilt2(imageList{index}.preprocImg,[3 3]); 
    imageList{index}.background = imopen(imageList{index}.preprocImg, strel('disk',15));
    imageList{index}.preprocImg = imageList{index}.preprocImg - imageList{index}.background;
    
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
    imageList{index}.bwImage = im2bw(imageList{index}.preprocImg, thresh);
    
    % (*) see below
    % remove objects from bwImage with pixelsize in [150, 900]
    
    imageList{index}.bwFilteredImage = ...
        imageList{index}.bwImage - bwareafilt(imageList{index}.bwImage, [100,800]);
    
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
   
    % use this cleaned image to calculate a more accurate threshold and
    % compute a bw image from that contains mostly DNA fragments/nucleosomes.
    
    t = threshold(threshAlgo1 , imageList{index}.filteredImage);
    imageList{index}.bwImgThickDna = im2bw(imageList{index}.filteredImage, t);
    
    % finally, remove any objects that might not be in the expected size
    % range of [150, 900]
    imageList{index}.bwImgThickDna = bwareafilt(imageList{index}.bwImgThickDna, [100,900]);
    
    
    %% Generate 1 pixel thin objects for length calculation
    imageList{index}.bwImgThinnedDna = bwmorph(imageList{index}.bwImgThickDna,'thin',Inf);
    
    
    %find circles, nuklei, centers, and radi
    [ imageList{index}.centers,imageList{index}.radii] = findNukleii(imageList{index}.bwImgThickDna, imageList{index}.preprocImg);
    
       
    %get properties of all objects on the ThickDnaBwImage and
    %ThinnedDnaBwImage
    imageList{index}.connectedThickDna = bwconncomp(imageList{index}.bwImgThickDna);
    imageList{index}.connectedThinnedDna = bwconncomp(imageList{index}.bwImgThinnedDna);
    region =  regionprops(imageList{index}.connectedThickDna, 'Centroid');
%     Kommentar
    imageList{index}.region = cat(1,region.Centroid);
    %create classobject for all fragments found on the image
    dnaCount = max(imageList{index}.connectedThickDna.NumObjects, imageList{index}.connectedThinnedDna.NumObjects);
    imageList{index}.dnaList =  cell(1,dnaCount);
    % calculate centers in int coord.
    centers = round(imageList{index}.centers);

    % convert centers from Point to index 
    imageList{index}.imgSize =  size(imageList{index}.bwImgThickDna);
    [m,n] = size(imageList{index}.bwImgThickDna);
    if ~isempty(centers)
        imageList{index}.indexcenters = centers(:,1) + (centers(:,2) -1)* m ; 
        
    end
%     Go through all objects within the connected Components and create DNA
%     Objects for them. DNABound if it is connected to a Nukleii and
%     DNAFree if not
    for dnaIndex = 1:dnaCount
%         Check if there are any Nukleii detected on the bwThinnedDNAImg
        if ~isempty(centers)
%             Check whether any of the Nukleii are attached to the current
%             DNA strand(connected Component)
        imageList{index}.contains = ismember(imageList{index}.indexcenters,imageList{index}.connectedThickDna.PixelIdxList{dnaIndex});
        
        end
%         Check if there was a Nukleii found that is attached to this
%         connectedComponent
        if sum(imageList{index}.contains)~= 0
%             find all Nukleii that are attached to this connected
%             Component
            nukleoIndecies = find(imageList{index}.contains);
%             create a Nukleii Object for all Nukleii found
            nukleos = cell(1,numel(nukleoIndecies));
            for i=1:numel(nukleoIndecies)
%                 Save all Nukleii found in a Cell
                nukleos{i} = nukleo(imageList{index}.centers(nukleoIndecies(i),:), ... 
                    imageList{index}.radii(nukleoIndecies(i),:));   
            end
%             create DNABound Object for every Object detected in the Image
%             Set Type,ConnectedComponents, position 
            imageList{index}.dnaList{dnaIndex} = DnaBound(imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}, ...
            imageList{index}.connectedThinnedDna.PixelIdxList{dnaIndex},imageList{index}.region(dnaIndex,:),'normal',nukleos);
%          Calculate angle between the Nukleii and the arms(the DNA Arms
%             imageList{index}.dnaList{dnaIndex}.angle = measure_angle(imageList{index}.dnaList{dnaIndex},imageList{index}.imgSize,0);
        else
%             When no Nukleii is attached, Create DNAFree Object and set
%             Type, ConnectedComponents and position 
            imageList{index}.dnaList{dnaIndex} = DnaFree(imageList{index}.connectedThickDna.PixelIdxList{dnaIndex}, ...
            imageList{index}.connectedThinnedDna.PixelIdxList{dnaIndex},imageList{index}.region(dnaIndex,:));
        end
%         
        imageList{index}.dnaList{dnaIndex}.number = dnaIndex;
    end
    
    if( strcmp(getenv('OS'),'Windows_NT'))
        
    imwrite(imageList{index}.preprocImg , ['..\pictures\preprocImg\' 'preproc' imageFolderObj(index).name ]);
    imwrite(imageList{index}.background , ['..\pictures\background\' 'bckground' imageFolderObj(index).name ]);
    imwrite(imageList{index}.bwImage , ['..\pictures\bwImage\' 'bw' imageFolderObj(index).name ]);
    imwrite(imageList{index}.bwFilteredImage , ['..\pictures\bwFilteredImage\' 'bwFiltered' imageFolderObj(index).name ]);
    imwrite(imageList{index}.filteredImage , ['..\pictures\filteredImage\' 'filtered' imageFolderObj(index).name ]);
    imwrite(imageList{index}.bwImgThickDna , ['..\pictures\bwImgThickDna\' 'bwThickDna' imageFolderObj(index).name ]);
%     imwrite(imageList{index}.bwImgDen , ['..\pictures\bwImgDen\' 'bwImgDen' imageFolderObj(index).name ]);
    imwrite(imageList{index}.bwImgThinnedDna , ['..\pictures\bwImgThinnedDna\' 'thinnedDna' imageFolderObj(index).name ]);
    
%     cd('..\biomedizinischebildanalyse') ;   
%         addpath(genpath('..\pictures\'));

    
    else
    end
    
    %% this was removed from (*). if we don't need it anymore, let's delete it
    %     fftImage = fftshift(fft2(imageList{index}.medImage));
    %     imageList{index}.fftImage = mat2gray(log(abs(fftImage)));
    %     t = threshold(threshAlgo,imageList{index}.fftImage);
    %     imageList{index}.fftbwImage = im2bw(imageList{index}.fftImage,t);
    %     [imageList{index}.cArray.center, imageList{index}.cArray.rad] = imfindcircles(imageList{index}.fftImage,500);
    %    imageList{index}.connected =  bwconncomp(imageList{index}.bwImage);
    %    imageList{index}.region = regionprops(imageList{index}.connected);
    
end
