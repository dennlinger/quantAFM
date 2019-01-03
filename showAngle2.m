function done = showAngle2(dna, mask, p, centers, p1, p2, x1, y1, x2, y2, flip1, flip2)
    img = zeros(dna.sizeImg);
    img(dna.bwImage)=1.;
    img(mask) = 0.75;
    img(dna.bwImageThinned) = 0.5;
    figure; imshow(img);
    hold on;
    viscircles( dna.attachedNukleo{1}.localCenter, dna.attachedNukleo{1}.rad);
    % scatter(y1,x1,'.', 'green')
    % scatter(y2,x2,'.', 'green')
     scatter(p(:,1),p(:,2), 'x','blue')
    % scatter(centers(1),centers(2), 'x','cyan')
    % plot(polyval(p1,x1),x1,'cyan');
    % plot(polyval(p2,x2), x2,'cyan');
    if flip1 == 1
        plot_x1 = y1
    else
        plot_x1 = x1
    end
    if flip2 == 1
        plot_x2 = y2
    else
        plot_x2 = x2
    end
    plot(polyval(p1,[plot_x1; centers(2)]),[plot_x1; centers(2)], 'blue');
    plot(polyval(p2,[plot_x2; centers(2)]),[plot_x2; centers(2)],'blue');
    w = waitforbuttonpress()
end