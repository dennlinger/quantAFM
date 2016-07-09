classdef DnaFree < DNA
    %DNAFREE Summary of this class goes here
    %   Detailed explanation goes here
    
    properties
    end
    
    methods
        function dnaObj = DnaFree(connectedThick,detail_thickDna, position)
            if nargin > 0
                dnaObj.position = position;
                dnaObj.connectedThick = connectedThick;
                dnaObj.bwImage = detail_thickDna;
         
                dnaObj.type = 'free';
                                
%                 delete all other objects on the subImage besides the Dna
%                 strand
                CC = bwconncomp(detail_thickDna);
                numPixels = cellfun(@numel, CC.PixelIdxList);
                [largestObj, idx] = max(numPixels);
                dnaObj.bwImage = false(size(dnaObj.bwImage));
                dnaObj.bwImage(CC.PixelIdxList{idx}) = true;
%%               Thin the subImage with Matlab function
                dnaObj.bwImageThinned = bwmorph(dnaObj.bwImage,'thin',Inf);
%%               ... using user-written implementation
%                dnaObj.bwImageThinned = thinningZhangSuen(dnaObj.bwImage);
%               Calculate connected Components PixelIdxList
                connectedThinned = bwconncomp(dnaObj.bwImageThinned);
                dnaObj.connectedThinned = connectedThinned.PixelIdxList{1};
                dnaObj.sizeImg = size(detail_thickDna);
               
            end
        end
    end
    
end

