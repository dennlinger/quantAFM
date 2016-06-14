
 
    imshowpair(imageList{index}.rawImage, imageList{index}.bwImgThickDna);
    hold on
    viscircles(imageList{index}.centers, imageList{index}.radii);
    hold on
    rad = ones(length(imageList{index}.region),1);
    viscircles(imageList{index}.region, rad);
%     text(imageList{index}.region(:,1), imageList{index}.region(:,2),...
%         [repmat( ' ', size(imageList{index}.region,1)),num2str((1:1:size(imageList{index}.region,1))')],'Color', 'b') ;
text(imageList{index}.region(:,1), imageList{index}.region(:,2),num2str([1:size(imageList{index}.region,1)]'));