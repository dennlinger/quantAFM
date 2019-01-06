function done = writeToCsvFile(filename, imageObj, purgeInvalid, verbose)

    global PIXELLENGTH PIXELPERNM REALVALUE;
    if (purgeInvalid)
        dnaCount = size(imageObj.purged, 2);
        purged_iterator = imageObj.purged;
    else
        dnaCount = size(imageObj.dnaList,2);

    end
    number = zeros(dnaCount,1) -1;
    xm = zeros(dnaCount,1) -1;
    ym = zeros(dnaCount,1) -1;
    radius = zeros(dnaCount,1) -1;
    length = zeros(dnaCount,1) -1;
    length_botharms = zeros(dnaCount,1) -1;
    short_arm = zeros(dnaCount,1) -1;
    long_arm = zeros(dnaCount,1) -1;
    hasNucleus = zeros(dnaCount,1) -1;
    isValid = zeros(dnaCount,1) -1;
    angle1 = zeros(dnaCount,1) -1;
    angle2 = zeros(dnaCount,1) -1;
    numNucleosomes = zeros(dnaCount,1) -1;
    if (verbose==1)
        short_arm_ratio = zeros(dnaCount,1) -1;
        short_arm_corrected_ratio = zeros(dnaCount,1) -1;
        short_arm_radius_ratio = zeros(dnaCount,1) -1;
        hundred_degrees = zeros(dnaCount,1) -1;
        angle1_classifier = zeros(dnaCount,1) -1;
        angle2_classifier = zeros(dnaCount,1) -1;
    end
    
    for dnaIndex =1:dnaCount
        if (purgeInvalid)
            curr = imageObj.dnaList{purged_iterator(dnaIndex)};
        else
            curr = imageObj.dnaList{dnaIndex};
        end
        number(dnaIndex,1) = curr.number;
        xm(dnaIndex,1) = curr.position(2);
        ym(dnaIndex,1) = curr.position(1);
        hasNucleus(dnaIndex,1) = curr.hasNucleus;
        isValid(dnaIndex,1) = curr.isValid;
        if (curr.hasNucleus == 0 ) % no nucleosome detected
            angle1(dnaIndex,1) = 0;
            angle2(dnaIndex,1) = 0;
            radius(dnaIndex,1) = 0;
            length(dnaIndex,1) = curr.length{1};
            length_botharms(dnaIndex,1) = 0;
            short_arm(dnaIndex,1) = 0;
            long_arm(dnaIndex,1) = 0;
            numNucleosomes(dnaIndex,1) = 0;
        else  % at least one nucleosome present
           angle1(dnaIndex,1) = curr.angle1;
           angle2(dnaIndex,1) = curr.angle2;
           radius(dnaIndex,1) = curr.attachedNukleo{1}.rad;
           numNucleosomes(dnaIndex,1) =  numel(curr.attachedNukleo) ;
           if size(curr.length, 2) == 3 % one short and one long arm found
                if curr.length{2} > curr.length{3}
                    short_arm(dnaIndex,1) = curr.length{3};
                    long_arm(dnaIndex,1) = curr.length{2};
                else
                    short_arm(dnaIndex,1) = curr.length{2};
                    long_arm(dnaIndex,1) = curr.length{3};
                end
                % now differ between total length and added length.
                length_botharms(dnaIndex,1) = curr.length{2} + curr.length{3};
%                 length(dnaIndex,1) = curr.length{2}+curr.length{3};
                length(dnaIndex,1) = curr.length{1};
                
                % if verbosity level is set, push more
                if (verbose==1)
                    short_arm_ratio(dnaIndex,1) = short_arm(dnaIndex,1) / ...
                        (short_arm(dnaIndex,1) + long_arm(dnaIndex,1));
                    short_arm_corrected_ratio(dnaIndex,1) = ...
                        (short_arm(dnaIndex,1)+radius(dnaIndex,1) - 5.5*PIXELPERNM ) / ...
                        (short_arm(dnaIndex,1) + long_arm(dnaIndex,1) + ...
                         2*radius(dnaIndex,1) - 11*PIXELPERNM);
                     short_arm_radius_ratio(dnaIndex,1) = (short_arm(dnaIndex,1)+radius(dnaIndex,1)) / ...
                        (short_arm(dnaIndex,1) + long_arm(dnaIndex,1) + ...
                         2*radius(dnaIndex,1));
                     if (angle1(dnaIndex,1) < 100 && angle2(dnaIndex,1) < 100)
                         hundred_degrees(dnaIndex,1) = 0;
                     else
                         hundred_degrees(dnaIndex,1) = 1;
                     end
                     angle1_classifier(dnaIndex,1) = floor(angle1(dnaIndex,1) / 30);
                     angle2_classifier(dnaIndex,1) = floor(angle2(dnaIndex,1) / 30);
                    
                end
           else
               short_arm(dnaIndex,1) = 0;
               long_arm(dnaIndex,1) = curr.length{1};
               %shouldn't long arm be 0?
%                long_arm(dnaIndex,1) = 0;
               length(dnaIndex,1) = curr.length{1};
           end 
        end
    end
    
    if (REALVALUE == 1)
       length = length * PIXELLENGTH;
       length_botharms = length_botharms * PIXELLENGTH;
       short_arm = short_arm * PIXELLENGTH;
       long_arm = long_arm * PIXELLENGTH;
       radius = radius * PIXELLENGTH;
    end
    
    if (verbose==1)
        T = table(number, xm, ym, length, hasNucleus, length_botharms, short_arm, long_arm ,...
            radius, isValid, angle1, angle2, numNucleosomes, short_arm_ratio, ...
            short_arm_corrected_ratio, short_arm_radius_ratio, hundred_degrees,...
            angle1_classifier, angle2_classifier);
    else
        T = table(number, xm, ym, length, hasNucleus, length_botharms, short_arm, long_arm ,...
            radius, isValid, angle1, angle2, numNucleosomes);
    end
    writetable(T, filename);
    done = 'done';
end