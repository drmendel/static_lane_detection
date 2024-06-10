% Close all open figures, clear workspace, and command window
close all;
clc;
clear;

% Define the folder containing images
folder = 'Roads';

% Load all PNG image files from the specified folder
imageFiles = dir(fullfile(folder, '*.png'));

% Create a figure to display the processing results
figure('Name', 'Searching for asphalt surfaces...');

% Check if any images are found in the specified folder
if isempty(imageFiles)
    disp('No images found in the specified folder.');
else
    % Loop through each image file
    for k = 1:length(imageFiles)
        % Get the file path of the current image
        filePath = fullfile(folder, imageFiles(k).name);
        % Read the image
        img = imread(filePath);
        


        % =========== ASPHALT DETECTION ===========
        
        % Define Region of Interest (ROI) for road area
        road_roiVertices = [0, 300; 400, 180; 800, 180; 1200, 400; 0, 400];
        road_roiMask = poly2mask(road_roiVertices(:, 1), road_roiVertices(:, 2), size(img, 1), size(img, 2));
        road_maskedImg = img .* uint8(road_roiMask);
        
        % Convert RGB image to HSV
        road_hsvImg = rgb2hsv(road_maskedImg);
        
        % Define thresholds for the HSV channels
        H_min = 0; H_max = 0.8;       % Wide range for hue, as gray has no specific hue
        S_min = 0; S_max = 0.25;       % Low saturation
        V_min = 0.1; V_max = 0.8;     % Mid-range value (brightness)
        
        % Create a binary mask based on the thresholds
        asphaltImg = (road_hsvImg(:,:,1) >= H_min & road_hsvImg(:,:,1) <= H_max) & ...
                   (road_hsvImg(:,:,2) >= S_min & road_hsvImg(:,:,2) <= S_max) & ...
                   (road_hsvImg(:,:,3) >= V_min & road_hsvImg(:,:,3) <= V_max);
        
        % Perform morphological operations to refine the asphalt mask
        asphaltImg = imclose(asphaltImg, strel("disk", 1));
        SE = strel("disk", 5);
        asphaltImg = imclose(imopen(asphaltImg, SE), SE);
        asphaltImg = imfill(asphaltImg, "holes");    
        asphaltImg = bwareaopen(asphaltImg, 7000);



        % =========== SIGN DETECTION ===========
        
        % Threshold the grayscale image to detect white signs
        sign_grayImg = rgb2gray(img);
        sign_binImg = sign_grayImg > 220;
        sign_binImg = sign_binImg & road_roiMask;
        sign_binImg = imclose(sign_binImg, strel('disk', 7));
        sign_binImg = bwareafilt(sign_binImg, [50 2000]);
        % sign_binImg = sign_binImg & asphaltImg;



        % =========== CENTERLINE AND SIGN DETECTION ===========
        
        % Define ROI for detecting mid-line
        line_roiVertices = [400, 350; 500, 200; 600, 200; 500, 350];
        line_roiMask = poly2mask(line_roiVertices(:, 1), line_roiVertices(:, 2), size(img, 1), size(img, 2));
        line_maskedImg = img .* uint8(line_roiMask);
        line_grayImg = rgb2gray(line_maskedImg);
        
        % Threshold the grayscale image to obtain binary image
        line_binImg = line_grayImg > 150;
        line_binImg = imerode(line_binImg, strel('disk', 1));

        % Detect dashed lines using region properties
        dashedLines = regionprops('table', line_binImg, 'Centroid');
        line_centroids = dashedLines.Centroid;

        % Fit a line to the centroids
        if size(line_centroids, 1) > 2
            [line_coefficients, ~] = polyfit(line_centroids(:,1), line_centroids(:,2), 1);
        else
            line_coefficients(1) = -1.1;
            line_coefficients(2) = 825;
        end

        disp(line_coefficients(1) + "x + " + line_coefficients(2));
        % Ensure line coefficients are within a reasonable range
        if line_coefficients(1) > -0.5 || line_coefficients(1) < -1.7
            line_coefficients(1) = -1.1;
            line_coefficients(2) = 825;
        end

        % Calculate Y coordinates using line equation
        xRange = 1:size(line_binImg, 2);
        yLine = line_coefficients(1) * xRange + line_coefficients(2);

        % Filter road lanes based on line position
        low_pass_line_filter = line_binImg;
        slope = line_coefficients(1);
        intercept = line_coefficients(2);
        [X, Y] = meshgrid(1:size(low_pass_line_filter, 2), 1:size(low_pass_line_filter, 1));
        lineY = slope * X + intercept;
        low_pass_line_filter = zeros(size(X));
        low_pass_line_filter(Y >= lineY) = 1;
        low_pass_line_filter(Y < lineY) = 0;
        high_pass_line_filter = ~low_pass_line_filter;

        % Extract red and green lanes
        binRedLane = asphaltImg & high_pass_line_filter;
        binGreenLane = asphaltImg & low_pass_line_filter;

        % Overlay red and green lanes on original image
        redOverlayColor = [1, 0, 0];
        greenOverlayColor = [0, 1, 0];
        redLane = cat(3, uint8(255*redOverlayColor(1)*binRedLane), uint8(255*redOverlayColor(2)*binRedLane), uint8(255*redOverlayColor(3)*binRedLane));
        greenLane = cat(3, uint8(255*greenOverlayColor(1)*binGreenLane), uint8(255*greenOverlayColor(2)*binGreenLane), uint8(255*greenOverlayColor(3)*binGreenLane));
        coloredLane = (img + redLane + greenLane);
        title("Asphalt regions", filePath);

        % Display the results
        subplot(2,1,1);
        imshow(sign_binImg);
        title("WHITE SIGNS");

        asphaltImg = coloredLane;

        subplot(2,1,2);
        imshow(asphaltImg);
        title("LANES");

        % Pause for visualization
        pause(0.25);
    end
end
