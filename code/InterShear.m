classdef InterShear < handle
    properties
        %% === General Paths and Settings ===
        work_folder = 'Results'     % Base directory to store all session results
        session_folder              % Full path to the current session's working directory       

        language_version    = 'de'; % Locale setting: 'de' = German (commas as decimal separator), 'en' = English (dots)
        path_reference              % Path to the reference .txt file
        path_measurement            % Path to the measurement .txt file

        raw_reference_data          % Raw text content from the reference file
        raw_measurement_data        % Raw text content from the measurement file

        w_reference_data            % Numeric matrix from parsed reference file
        w_measurement_data          % Numeric matrix from parsed measurement file

        w_reference_trans           % Transformed reference data (after coordinate conversion)
        w_measurement_trans         % Transformed measurement data (after coordinate conversion)
      
        %% === Preprocessing ===
        w_cut                       % Extracted displacement field after optional cutoff (if no limits are set, the output corresponds to the input)
  
        % Cutoff area limits (NaN = no cutoff)
        x_min_cutoff = NaN;
        x_max_cutoff = NaN;
        y_min_cutoff = NaN;
        y_max_cutoff = NaN;

        transf_coord = false;       % Flag to enable coordinate system transformation

        %% === Camera and Grid Settings ===
        resolutionX   = 1900;       % Camera width in pixels
        resolutionY   = 1200;       % Camera height in pixels

        x_int                       % X-grid points for interpolation
        y_int                       % Y-grid points for interpolation
        w_int                       % Interpolated displacement field (w)
        w_int_smooth                % Smoothed displacement field (after Gaussian filter to reduce numerical noise)

        %% === Smoothing Parameters ===
        sigma                   	% User-defined or suggested sigma for Gaussian smoothing
        sigma_suggested             % Auto-suggested sigma based on point density

        %% === Gradient & Microstrain Fields ===
        dwdx                        % Spatial gradient ∂w/∂x (mm/mm)
        dwdy                        % Spatial gradient ∂w/∂y (mm/mm)
        dwdx_microstrain            % ∂w/∂x converted to microstrain (µε)
        dwdy_microstrain            % ∂w/∂y converted to microstrain (µε)
        
        min_dwdx                    % Minimum value of dwdx_microstrain
        max_dwdx                    % Maximum value of dwdx_microstrain
        min_dwdy                    % Minimum value of dwdy_microstrain
        max_dwdy                    % Maximum value of dwdy_microstrain

        %% === Phase Shift Calculation ===
        illumination_angle  = 0;    % Illumination angle in degrees (optional, not used directly yet)
        method                      % Method used for phase calculation: 'shear_x', 'shear_y', or 'holography'

        %% === Plot Settings ===
        plot_language = 'en'        % Language for plots: 'de' or 'en'

    end

    methods
        function obj = InterShear()
            % InterShear – Constructor for the InterShear class.
            %
            % Description:
            %   Creates an instance of the InterShear class.
            %   If the working folder (obj.work_folder) does not exist, it creates it.
            %
            % Inputs:
            %   None
            %
            % Outputs:
            %   obj – An instance of the InterShear class.
            
            % Create working folder if it does not exist
            if ~exist(obj.work_folder, 'dir')
                mkdir(obj.work_folder);
            end
        end

        function DataImporter(obj, path_reference, path_measurement, language_version, session_name)
            % DATAIMPORTER – Initializes session folder and sets file paths
            %
            % Description:
            %   Creates a session folder inside the working folder, named either by the provided 
            %   session name or a timestamp if no session name is given. Sets the paths for 
            %   reference and measurement data. Also sets the system language version based 
            %   on input or defaults to English. Finally, triggers data import by calling 
            %   obj.importData().
            %
            % Inputs:
            %   - obj (object): Instance of the class calling the method
            %   - path_reference (string): File path to the reference data
            %   - path_measurement (string): File path to the measurement data
            %   - language_version (string, optional): Language code ('de' for German, defaults to 'en')
            %   - session_name (string, optional): Name for the session folder; if empty or missing, 
            %     a timestamp-based name is used
            %
            % Outputs:
            %   - None
            %
            % Notes:
            %   - Creates the session folder if it does not already exist
            %   - If unsupported language_version is provided, defaults to English with a warning
            %   - Requires obj.importData() method to be implemented for data import
            
            % If session_name is not provided or empty, create one based on current timestamp
            if nargin <5 || isempty(session_name)
                session_name = char(datetime('now','Format','yyyyMMdd_HHmmss')); % z.B. 20250710_153000
            end

            % Construct the full path for the session folder inside the working folder
            obj.session_folder = fullfile(obj.work_folder, session_name);
            
            % Create the session folder if it does not already exist
            if ~exist(obj.session_folder, 'dir')
                mkdir(obj.session_folder);
            end

            % Assign the reference and measurement paths if provided
            if nargin > 0
                obj.path_reference = path_reference;
                obj.path_measurement = path_measurement;
            end

            % Determine the language version; default to 'en' if not provided or unsupported
            if nargin > 2
                if strcmpi(language_version, 'de') % Case-insensitive check for German
                    obj.language_version = 'de';
                else
                    warning('Unsupported language version "%s". Defaulting to "en".', language_version);
                    obj.language_version = 'en';
                end
            else
                obj.language_version = 'en'; % Default language
            end

            % Call the method to import data
            obj.importData();
        end

        function importData(obj)
            % IMPORTDATA – Imports and preprocesses simulation data files
            %
            % Description:
            %   Reads simulation data from reference and measurement text files in ANSYS-style 
            %   node displacement format. It cleans the data depending on the language setting 
            %   (handles decimal and list separators), saves cleaned versions in the session 
            %   folder, and loads the numeric data into the object's properties for further use.
            %
            % Inputs:
            %   - obj (object): Instance of the class containing file paths and settings
            %
            % Outputs:
            %   - None
            %
            % Notes:
            %   - Input files must be pre-cleaned of headers and contain no NaN or empty values
            %   - Data files must have identical number of rows and be structured as:
            %       Column 1: X-coordinate
            %       Column 2: Y-coordinate
            %       Column 3: Z-coordinate
            %       Column 4: Displacement in Z (W)
            %   - Coordinates and displacements must be in millimeters [mm]
            %   - Handles decimal and delimiter format differences based on language ('de' or 'en')
            %   - Stores cleaned numeric data in obj.w_reference_data and obj.w_measurement_data


            % Load raw text content from provided file paths
            obj.raw_reference_data = fileread(obj.path_reference);
            obj.raw_measurement_data = fileread(obj.path_measurement);

            cleaned_ref = obj.raw_reference_data;
            cleaned_meas = obj.raw_measurement_data;

            % Convert German format commas to dots for decimals and semicolons to commas for separators
            if strcmp(obj.language_version, 'de')
                cleaned_ref = strrep(cleaned_ref, ',', '.'); % decimal comma to dot
                cleaned_meas = strrep(cleaned_meas, ',', '.');

                cleaned_ref = strrep(cleaned_ref, ';', ','); % semicolon to comma as delimiter
                cleaned_meas = strrep(cleaned_meas, ';', ',');
            end

            % Define paths for cleaned CSV files inside the current session folder
            cleaned_ref_path = fullfile(obj.session_folder, 'cleaned_reference.csv');
            cleaned_meas_path = fullfile(obj.session_folder, 'cleaned_measurement.csv');

            % Write cleaned string data to new files
            fid = fopen(cleaned_ref_path, 'w'); fwrite(fid, cleaned_ref); fclose(fid);
            fid = fopen(cleaned_meas_path, 'w'); fwrite(fid, cleaned_meas); fclose(fid);

            % Read numeric data from cleaned CSV files into object properties
            obj.w_reference_data = readmatrix(cleaned_ref_path);
            obj.w_measurement_data = readmatrix(cleaned_meas_path);
        end
          
        function transformCoordinates(obj, transf_coord, cutoffs)
            % TRANSFORMCOORDINATES – Applies coordinate transformations and extracts cutout area
            %
            % Description:
            %   Transforms coordinate data of reference and measurement sets by optionally swapping
            %   X and Y axes and inverting the Z-axis direction to match measurement conventions.
            %   Ensures all X and Y coordinates are positive by shifting if necessary because
            %   interpolation routines require positive coordinates. Extracts a subset of data based
            %   on given cutoff boundaries and shifts the cutout area to start at the origin.
            %
            % Inputs:
            %   - transf_coord (logical, optional): Flag to apply coordinate transformation (default: obj.transf_coord)
            %   - cutoffs (struct, optional): Struct with fields x_min, x_max, y_min, y_max defining
            %     the cutoff region (default: uses obj.x_min_cutoff, obj.x_max_cutoff, etc.)
            %
            % Outputs:
            %   - None
            %
            % Notes:
            %   - Coordinate conventions:
            %       * X and Y lie in the component surface plane (in-plane)
            %       * Z points out of the component surface towards the sensor (out-of-plane)
            %       * Positive Z means displacement towards sensor
            %   - Negative X or Y coordinates are shifted to zero or positive values
            %   - If transformation is disabled, coordinates are assumed correct from FEM software
            %   - The method checks coordinate consistency between reference and measurement data
            %   - Applies cutoff filtering to extract region of interest and shifts cutout to origin

            % Use internal property values if inputs not provided
            if nargin < 2 || isempty(transf_coord)
                transf_coord = obj.transf_coord;
            end
        
            if nargin < 3 || isempty(cutoffs)
                x_min_cut = obj.x_min_cutoff;
                x_max_cut = obj.x_max_cutoff;
                y_min_cut = obj.y_min_cutoff;
                y_max_cut = obj.y_max_cutoff;
            else
                x_min_cut = cutoffs.x_min;
                x_max_cut = cutoffs.x_max;
                y_min_cut = cutoffs.y_min;
                y_max_cut = cutoffs.y_max;
            end

            % Initialize transformed data with original data
            obj.w_reference_trans = obj.w_reference_data;
            obj.w_measurement_trans = obj.w_measurement_data;
            
            % Apply coordinate transformation if enabled
            if transf_coord
                % Swap X and Y coordinates
                obj.w_reference_trans(:, [1 2]) = obj.w_reference_trans(:, [2 1]);
                obj.w_measurement_trans(:, [1 2]) = obj.w_measurement_trans(:, [2 1]);
        
                % Invert Z coordinate and displacement
                obj.w_reference_trans(:, 3:4) = -obj.w_reference_trans(:, 3:4);
                obj.w_measurement_trans(:, 3:4) = -obj.w_measurement_trans(:, 3:4);
        
                disp('Coordinate transformation applied: X↔Y swapped, Z inverted.');
            else
                disp('No coordinate transformation applied.');
            end
            
            % Shift coordinates to ensure no negative values
            min_x = min([obj.w_reference_trans(:,1); obj.w_measurement_trans(:,1)]);
            min_y = min([obj.w_reference_trans(:,2); obj.w_measurement_trans(:,2)]);

            if min_x < 0 || min_y < 0
                obj.w_reference_trans(:,1) = obj.w_reference_trans(:,1) - min_x;
                obj.w_reference_trans(:,2) = obj.w_reference_trans(:,2) - min_y;
                obj.w_measurement_trans(:,1) = obj.w_measurement_trans(:,1) - min_x;
                obj.w_measurement_trans(:,2) = obj.w_measurement_trans(:,2) - min_y;
        
                disp('Negative X or Y coordinates detected and shifted to positive domain.');
            else
                disp('No negative X or Y coordinates found; no shift applied.');
            end

            % Check if X/Y coordinates of reference and measurement match
            if ~isequal(obj.w_reference_trans(:,1:2), obj.w_measurement_trans(:,1:2))
                warning('X/Y coordinates of reference and measurement data do not match!');
            end

            % Calculate displacement difference between measurement and reference
            displacement_diff = obj.w_measurement_trans(:,4) - obj.w_reference_trans(:,4);

            % Combine coordinates with displacement difference
            combined_data = [obj.w_reference_trans(:,1:3), displacement_diff];
            
            % Determine bounds of combined data
            x_min = min(combined_data(:,1));
            x_max = max(combined_data(:,1));
            y_min = min(combined_data(:,2));
            y_max = max(combined_data(:,2));
        
            orig_limits = [x_min, x_max, y_min, y_max];
        
            % Validate cutoff boundaries, use data limits if cutoffs invalid
           if isnan(x_min_cut) || x_min_cut < x_min || x_min_cut > x_max
                x_min_cut = x_min;
            end
            if isnan(x_max_cut) || x_max_cut > x_max || x_max_cut < x_min
                x_max_cut = x_max;
            end
            if isnan(y_min_cut) || y_min_cut < y_min || y_min_cut > y_max
                y_min_cut = y_min;
            end
            if isnan(y_max_cut) || y_max_cut > y_max || y_max_cut < y_min
                y_max_cut = y_max;
            end
        
            % Extract data within cutoff region
            idx = combined_data(:,1) >= x_min_cut & combined_data(:,1) <= x_max_cut & ...
                  combined_data(:,2) >= y_min_cut & combined_data(:,2) <= y_max_cut;
        
            cut_data = combined_data(idx, :);
        
            % Shift cutout data coordinates to start at origin
            cut_data(:,1) = cut_data(:,1) - x_min_cut;
            cut_data(:,2) = cut_data(:,2) - y_min_cut;
        
            % Save the cut and shifted data
            obj.w_cut = cut_data;
        
            % Display info about cutoff application
            if x_min_cut > orig_limits(1) || x_max_cut < orig_limits(2) || ...
               y_min_cut > orig_limits(3) || y_max_cut < orig_limits(4)
                disp('Data cut applied and coordinates shifted to origin.');
            else
                disp('No cutoff applied (entire area retained).');
            end
        end

        function plotAndSaveFigure(obj, data, climVals, titleText, baseFilename, folderPath, useGrayscale)
            % PLOTANDSAVEFIGURE – Plots data as an image and saves the figure in multiple formats
            %
            % Description:
            %   This method visualizes 2D data as an image using specified axes, applies optional
            %   color limits and colormap (grayscale or parula), sets axis labels and a formatted title,
            %   then saves the figure to disk in PNG, FIG, and SVG formats within a specified folder.
            %   The figure is created invisibly (not shown on screen) and closed after saving.
            %
            % Inputs:
            %   - data (numeric matrix): 2D data to be displayed as an image.
            %   - climVals (1x2 numeric vector or empty): Color axis limits; if empty, defaults are used.
            %   - titleText (string, char, or cell): Title text for the plot (supports LaTeX interpreter).
            %   - baseFilename (string or char): Base name for saved files (without extension).
            %   - folderPath (string, optional): Folder to save files; defaults to './figures' if empty.
            %   - useGrayscale (logical, optional): Flag to use grayscale colormap instead of parula (default: false).
            %
            % Outputs:
            %   - None
            %
            % Notes:
            %   - Requires obj.x_int and obj.y_int properties to define axes for imagesc.
            %   - Saves figure in three formats: PNG, MATLAB FIG, and SVG.
            %   - Throws error if titleText is not string, char, or cell array.
            %   - Font is set to Times New Roman with LaTeX interpreter for labels and title.

            % Set default folderPath if not provided
            if nargin < 6 || isempty(folderPath)
                folderPath = fullfile(pwd, 'figures');
            end

            % Create folder if it does not exist
            if ~exist(folderPath, 'dir')
                mkdir(folderPath);
            end

            % Default useGrayscale to false if not provided
            if nargin < 7
                useGrayscale = false;
            end
            
            % Create invisible figure
            fig = figure('Visible', 'off');

            % Display data as image with given x and y coordinates
            imagesc(obj.x_int, obj.y_int, data);
            axis equal tight;
            set(gca, 'YDir', 'normal');

            % Customize axis font
            ax = gca;
            ax.FontSize = 12;
            ax.FontName = 'Times New Roman';
            
            % Apply color limits if specified
            if ~isempty(climVals)
                clim(climVals);
            end
            
            % Choose colormap
            if useGrayscale
                colormap(gray(256));
            else
                colormap(parula);
            end
            
            % Label axes with LaTeX interpreter
            xlabel('x [mm]', 'Interpreter', 'latex', 'FontSize', 12, 'FontName', 'Times New Roman');
            ylabel('y [mm]', 'Interpreter', 'latex', 'FontSize', 12, 'FontName', 'Times New Roman');
            
            % Process title input
            if iscell(titleText)
                tStr = titleText;
            elseif isstring(titleText) || ischar(titleText)
                tStr = char(titleText);
            else
                error('Invalid titleText format: must be string, char, or cell.');
            end
            
            % Set title with formatting
            title(tStr, 'Interpreter', 'latex', 'FontSize', 14, 'FontName', 'Times New Roman', ...
                  'Units', 'normalized', 'Position', [0.5, 1.05, 0]);
            
            % Add colorbar with LaTeX tick labels
            cb = colorbar(ax, 'eastoutside');
            cb.TickLabelInterpreter = 'latex';
            cb.FontName = 'Times New Roman';
        
            % Save figure in multiple formats
            saveas(fig, fullfile(folderPath, baseFilename + ".png"));
            saveas(fig, fullfile(folderPath, baseFilename + ".fig"));
            saveas(fig, fullfile(folderPath, baseFilename + ".svg"));
            
            % Close figure to free resources
            close(fig); 
        end

        function interpolateToCameraGrid(obj)
            % INTERPOLATETOCAMERAGRID – Interpolates displacement data onto a regular camera grid
            %
            % Description:
            %   This method interpolates the preprocessed cut displacement data (`obj.w_cut`) onto a
            %   regularly spaced 2D grid based on the defined camera resolution (`resolutionX` × `resolutionY`).
            %   It uses linear interpolation to map scattered data onto the grid and fills in missing
            %   values using linear and nearest-neighbor methods to ensure continuity.
            %   The resulting interpolated surface (`obj.w_int`) is visualized and saved to disk.
            %
            % Inputs:
            %   - None (uses internal object properties: w_cut, resolutionX, resolutionY, session_folder)
            %
            % Outputs:
            %   - None (saves interpolated result to obj.w_int and a plot to the session folder)
            %
            % Notes:
            %   - Requires obj.w_cut to be initialized (by running transformCoordinates first).
            %   - Uses `griddata` for interpolation and `fillmissing` to handle NaN values.
            %   - Visualization is saved using plotAndSaveFigure.
            %   - Output figure shows out-of-plane displacement in micrometers.
            
            % Check if required data is available
            if isempty(obj.w_cut)
                error('No cut data available. Please run transformCoordinates() first.');
            end

             % Define interpolation domain based on max coordinates
            max_x = max(obj.w_cut(:, 1));
            max_y = max(obj.w_cut(:, 2));

            % Generate regularly spaced grid vectors based on camera resolution
            obj.x_int = linspace(0, max_x, obj.resolutionX);
            obj.y_int = linspace(0, max_y, obj.resolutionY);
            [Xq, Yq] = meshgrid(obj.x_int, obj.y_int);

            % Interpolate displacement data onto the regular grid
            obj.w_int = griddata(obj.w_cut(:,1), obj.w_cut(:,2), obj.w_cut(:,4), Xq, Yq, 'linear');

            % Interpolate displacement data onto the regular grid
            obj.w_int = fillmissing(obj.w_int, 'linear', 2);  % Fill row-wise (horizontally)
            obj.w_int = fillmissing(obj.w_int, 'nearest', 1); % Fill column-wise (vertically)

            disp('Displacement data interpolated onto regular camera grid.');
            
            % Define title and filename for plot
            titleW = {'Out-of-plane displacement w [$\mu$m]'};
            filenameW = "w_int";

            % Plot and save the interpolated result
            obj.plotAndSaveFigure(obj.w_int, [], titleW, filenameW, fullfile(obj.session_folder, "figures"));
        end

        function plotInterpolatedField(obj)
            % PLOTINTERPOLATEDFIELD – Displays the interpolated displacement field as a color image
            %
            % Description:
            %   This method visualizes the raw interpolated displacement data stored in `obj.w_int`
            %   using a 2D color plot. The X and Y axes represent the spatial dimensions in millimeters,
            %   while the color indicates the magnitude of the out-of-plane displacement.
            %   This plot helps assess the structure of the interpolated field before any filtering
            %   or further processing is applied.
            %
            % Inputs:
            %   - None (uses internal object properties: w_int, x_int, y_int)
            %
            % Outputs:
            %   - None (opens a new figure window with the visualization)
            %
            % Notes:
            %   - Requires that interpolation has already been performed via interpolateToCameraGrid().
            %   - This function does not apply any smoothing or filtering.
            %   - The color scale is automatically adjusted based on the data range.

            % Check if interpolated data exists
            if isempty(obj.w_int)
                error('Interpolated data (w_int) is empty. Please run interpolateToCameraGrid() first.');
            end
            
            % Create a new figure for visualization
            figure('Name', 'Interpolated Displacement Field', 'NumberTitle', 'off');

            % Display the interpolated data as an image
            imagesc(obj.x_int, obj.y_int, obj.w_int);

            % Set axis properties
            axis image;
            set(gca, 'YDir', 'normal'); % Korrigiert Y-Achse
            colorbar;

            % Annotate the plot
            title('Interpolated Displacement Field (Unfiltered)');
            xlabel('X [mm]');
            ylabel('Y [mm]');
        end

        function suggestSigmaByPointDensity(obj)
            % SUGGESTSIGMABYPOINTDENSITY – Estimates a suitable Gaussian smoothing parameter
            %
            % Description:
            %   This method estimates an appropriate Gaussian filter width (sigma) based on
            %   the spatial density of the original displacement measurement points.
            %   It assumes that noise suppression via smoothing should be adapted to the average 
            %   point spacing. A heuristic factor (~4× the average spacing) is used to compute 
            %   a recommended sigma value. Several filtered versions of the interpolated field
            %   are displayed to visually compare the effects of different sigma values.
            %
            % Inputs:
            %   - None (uses internal object properties: w_cut, w_int, resolutionX, resolutionY)
            %
            % Outputs:
            %   - None (displays multiple smoothed versions of the displacement field in subplots)
            %
            % Notes:
            %   - Requires that `interpolateToCameraGrid()` has been called beforehand.
            %   - The suggested sigma value is stored in the property `obj.sigma_suggested`.
            %   - The original measurement density is used for sigma estimation, not the interpolated data.

            % Validate input data
            if isempty(obj.w_cut)
                error('Original measured points field w_cut is empty. Cannot estimate point density.');
            end
            if isempty(obj.w_int)
                error('Interpolated field w_int is empty. Run interpolateToCameraGrid() first.');
            end
        
            % Count valid measurement points (non-NaN)
            numPoints = sum(~isnan(obj.w_cut(:)));
        
            % Calculate pixel area of interpolation grid
            pixelArea = obj.resolutionX * obj.resolutionY;
        
            % Estimate point density (points per pixel)
            density = numPoints / pixelArea;
        
            % Compute average spacing based on density
            avgSpacing = sqrt(1 / density);
        
            % Suggest sigma as 4× average spacing (common heuristic)
            %sigmaSuggested = max(1, round(avgSpacing * 3)); 
            sigmaSuggested = avgSpacing * 4;  % Keep floating point value
            
            obj.sigma_suggested = sigmaSuggested;

            fprintf('Suggested sigma based on point density: %.2f\n', sigmaSuggested);
        
            % Define a set of sigma values to visualize
            sigmaList = unique([1, 3, sigmaSuggested, 7, 10]);
            
            % Create figure to compare effects of different sigmas
            figure('Name', 'Gaussian Smoothing with Different Sigmas', 'NumberTitle', 'off');
        
            for i = 1:length(sigmaList)
                sigma = sigmaList(i);

                % Apply Gaussian smoothing
                w_smooth = imgaussfilt(obj.w_int, sigma);
                
                % Plot smoothed result
                subplot(2, 3, i);
                imagesc(obj.x_int, obj.y_int, w_smooth);
                axis image;
                set(gca, 'YDir', 'normal');
                colorbar;
                title(sprintf('\\sigma = %d', sigma));
                xlabel('X [mm]');
                ylabel('Y [mm]');
            end
        
            % Also display the unsmoothed field
            subplot(2, 3, length(sigmaList)+1);
            imagesc(obj.x_int, obj.y_int, obj.w_int);
            axis image;
            set(gca, 'YDir', 'normal');
            colorbar;
            title('Original (unsmoothed)');
            xlabel('X [mm]');
            ylabel('Y [mm]');
        end

        function applyGaussianSmoothing(obj, sigma_manual)
            % APPLYGAUSSIANSMOOTHING – Applies Gaussian filter to displacement field
            %
            % Description:
            %   Applies Gaussian smoothing to the interpolated out-of-plane displacement field 
            %   (obj.w_int) using a user-specified standard deviation (sigma). 
            %   If no sigma is provided, the method will attempt to use a previously 
            %   suggested value (obj.sigma_suggested). This reduces high-frequency noise 
            %   while preserving larger structural features in the data.
            %
            % Inputs:
            %   - sigma_manual (double): Standard deviation for Gaussian kernel. If omitted, 
            %     the method will use obj.sigma_suggested (requires prior call to 
            %     suggestSigmaByPointDensity()).
            %
            % Outputs:
            %   - None (updates internal property obj.w_int_smooth and saves figure)
            %
            % Notes:
            %   - Requires that obj.w_int is already computed (run interpolateToCameraGrid() first).
            %   - Smoothed results are saved as image files in the session's "figures" folder.
            %   - The smoothing uses MATLAB's imgaussfilt() function.

            % Check if interpolated field is available
            if isempty(obj.w_int)
                error('Interpolated field w_int is empty. Run interpolateToCameraGrid() first.');
            end
            
            % Determine which sigma to use
            if nargin < 2 || isempty(sigma_manual)
                % Use previously suggested sigma if no manual value is given
                if isempty(obj.sigma_suggested)   
                    error('No sigma specified and no suggested sigma available. Run suggestSigmaByPointDensity() first or provide sigma manually.');
                else
                    obj.sigma = obj.sigma_suggested;
                    fprintf('Using suggested sigma = %.2f.\n', obj.sigma);
                end
            else
                % Use manually provided sigma
                obj.sigma = sigma_manual;
                fprintf('Manual sigma = %.2f applied.\n', obj.sigma);
            end
            
            % Apply Gaussian smoothing to interpolated field
            obj.w_int_smooth = imgaussfilt(obj.w_int, obj.sigma);
            disp('Gaussian smoothing applied to interpolated displacement field.');
            
            % Prepare figure title and filename with sigma value
            sigmaStr = sprintf('%.2f', obj.sigma);
            titleW = {['Smoothed out-of-plane displacement w [$\mu$m], ' ...
                [' $\sigma$ = '], sigmaStr]
                };
            filenameW = "w_smooth_sigma" + sigmaStr;
            
            % Plot and save smoothed result
            obj.plotAndSaveFigure(obj.w_int_smooth, [], titleW, filenameW, fullfile(obj.session_folder, "figures"));
        end

        function calculateStrainFlieds(obj)
            % CALCULATESTRAINFIELDS – Computes strain fields from displacement
            %
            % Description:
            %   Calculates the spatial gradients of the smoothed out-of-plane displacement 
            %   field (w_int_smooth) in x- and y-direction to estimate surface slopes or 
            %   strain-like quantities. The gradients are converted into microstrain units (με).
            %   Additionally, the function stores the min/max values of both fields and visualizes 
            %   the results using color maps.
            %
            % Inputs:
            %   - None (uses internal properties of the object)
            %
            % Outputs:
            %   - None (results are stored in the object and figures are saved)
            %
            % Notes:
            %   - Requires a smoothed displacement field (obj.w_int_smooth); run applyGaussianSmoothing() first.
            %   - Assumes that obj.x_int and obj.y_int are defined and match the resolution.
            %   - Derivatives are computed using MATLAB’s gradient() function, taking care to match
            %     axis order (Y before X).
            %   - Plots are saved to the "figures" subfolder in the session directory.
            
            % Check if smoothed displacement field exists
            if isempty(obj.w_int_smooth)
                error('Smoothed displacement field is empty. Run applyGaussianSmoothing() first.');
            end
            
            % Calculate spatial step sizes in x and y directions
            dx = (max(obj.x_int(:)) - min(obj.x_int(:))) / (obj.resolutionX - 1);
            dy = (max(obj.y_int(:)) - min(obj.y_int(:))) / (obj.resolutionY - 1);
        
            % Compute gradient of w with respect to x and y
            % Note: gradient returns [∂w/∂x, ∂w/∂y]
            [obj.dwdx, obj.dwdy] = gradient(obj.w_int_smooth, dy, dx);
        
            % Convert gradients from mm/mm to microstrain [με]
            obj.dwdx_microstrain = obj.dwdx * 1e6;
            obj.dwdy_microstrain = obj.dwdy * 1e6;
        
            % Store diagnostic min/max values
            obj.min_dwdx = min(obj.dwdx_microstrain(:), [], 'omitnan');
            obj.max_dwdx = max(obj.dwdx_microstrain(:), [], 'omitnan');
            obj.min_dwdy = min(obj.dwdy_microstrain(:), [], 'omitnan');
            obj.max_dwdy = max(obj.dwdy_microstrain(:), [], 'omitnan');
        
            % Print summary to console
            fprintf('--- Microstrain dwdx ---\n');
            fprintf('Min: %.2f με\nMax: %.2f με\n', obj.min_dwdx, obj.max_dwdx);
            fprintf('--- Microstrain dwdy ---\n');
            fprintf('Min: %.2f με\nMax: %.2f με\n', obj.min_dwdy, obj.max_dwdy);
            
            % Prepare figure and filename for dwdx plot
            sigmaStr = sprintf('%.2f', obj.sigma);
            titleW = {['Slope in x-Direction $\frac{\partial w}{\partial x} \; [\mu\varepsilon]$,' ...
                [' $\sigma$ = '], sigmaStr]
                };
            filenameW = "dwdx_sigma" + sigmaStr;
            
            obj.plotAndSaveFigure(obj.dwdx_microstrain, [], titleW, filenameW, fullfile(obj.session_folder, "figures"));

            % Prepare figure and filename for dwdy plot
            sigmaStr = sprintf('%.2f', obj.sigma);
            titleW = {['Slope in y-Direction $\frac{\partial w}{\partial y} \; [\mu\varepsilon]$,' ...
                [' $\sigma$ = '], sigmaStr]
                };
            filenameW = "dwdy_sigma" + sigmaStr;
            
            obj.plotAndSaveFigure(obj.dwdy_microstrain, [], titleW, filenameW, fullfile(obj.session_folder, "figures"));
        end
      
        function remodulatePhaseShift(obj, method, wavelength_nm, shear_mm)
            % REMODULATEPHASESHIFT – Computes and visualizes remodulated phase shifts
            %
            % Description:
            %   Calculates phase shift distributions for different optical measurement methods,
            %   such as shearography or holography, based on deformation gradients or 
            %   displacement fields. The phase shift is computed using the optical path difference,
            %   normalized to the laser wavelength, and remodulated to the range [-1, 1].
            %   This calculation assumes normal (0°) illumination with
            %   respect to the surface. The resulting phase shift field is visualized and saved.
            %
            % Inputs:
            %   - method (char): Specifies the optical method. Options:
            %       'shear_x' or 'dwdx'      → uses ∂w/∂x
            %       'shear_y' or 'dwdy'      → uses ∂w/∂y
            %       'holography' or 'w'      → uses smoothed displacement field
            %   - wavelength_nm (numeric): Laser wavelength in nanometers
            %   - shear_mm (numeric): Shear distance in millimeters (ignored for holography)
            %
            % Outputs:
            %   - None (results are visualized and saved to file)
            %
            % Notes:
            %   - For 'shear_x' and 'shear_y', the corresponding gradient fields (dwdx/dwdy)
            %     must be computed beforehand using calculateStrainFields().
            %   - For 'holography', the smoothed displacement field must be available via applyGaussianSmoothing().
            %   - Phase shift is computed using:
            %         Noop = (2 * deformation * shear) / wavelength
            %     and remodulated to the interval [-1, 1].
            %   - The visualization uses grayscale and is language-adaptive (DE/EN).
            
            
            % Determine deformation field based on selected method
            switch lower(method)
                case {'shear_x', 'dwdx'}
                    % For shear in x-direction, use dwdx strain component
                    if isempty(obj.dwdx)
                        error('No dwdx data available. Run calculateStrainFields() first.');
                    end
                    deformation = obj.dwdx;
                    
                    % German and English title strings for plot
                    titleStr_de = {
                        'Phasenverschiebung '
                        sprintf('Wellenlänge: %d nm', wavelength_nm)
                        sprintf('Shearbetrag: %.2f mm', shear_mm)
                        '$\partial w / \partial x$'
                    };
                    titleStr_en = {
                        'Phase shift'
                        sprintf('Wavelength: %d nm', wavelength_nm)
                        sprintf('Shear: %.2f mm', shear_mm)
                        '$\partial w / \partial x$'
                    };
                    filename_base = sprintf('dwdx_phaseshift_%dnm_%.2fmm_sigma%.2f', wavelength_nm, shear_mm, obj.sigma);

                case {'shear_y', 'dwdy'}
                    % For shear in y-direction, use dwdy strain component
                    if isempty(obj.dwdy)
                        error('No dwdy data available. Run calculateStrainFields() first.');
                    end
                    deformation = obj.dwdy;

                    titleStr_de = {
                        'Phasenverschiebung '
                        sprintf('Wellenlänge: %d nm', wavelength_nm)
                        sprintf('Shearbetrag: %.2f mm', shear_mm)
                        '$\partial w / \partial y$'
                    };
                    titleStr_en = {
                        'Phase shift'
                        sprintf('Wavelength: %d nm', wavelength_nm)
                        sprintf('Shear: %.2f mm', shear_mm)
                        '$\partial w / \partial y$'
                    };
                    filename_base = sprintf('dwdy_phaseshift_%dnm_%.2fmm_sigma%.2f', wavelength_nm, shear_mm, obj.sigma);

                case {'holography', 'w'}
                    % For holography, use smoothed displacement field
                    if isempty(obj.w_int_smooth)
                        error('No smoothed displacement field available. Run applyGaussianSmoothing() first.');
                    end
                    deformation = obj.w_int_smooth;

                    % Override shear for holography case (no shear)
                    shear_mm = 1;   

                    titleStr_de = {
                        'Phasenverschiebung '
                        sprintf('Wellenlänge: %d nm', wavelength_nm)
                    };
                    titleStr_en = {
                        'Phase shift'
                        sprintf('Wavelength: %d nm', wavelength_nm)
                    };
                    filename_base = sprintf('w_phaseshift_%dnm_sigma%.2f', wavelength_nm, obj.sigma);

                otherwise
                    error('Invalid method. Use ''shear_x'', ''shear_y'', or ''holography''.');
            end
            

            % Remodulation calculation
            % Calculate normalized optical path difference (Noop)
            % Note: Illumination is assumed to be normal incidence (0°),
            %       so the optical path change = 2 * displacement * shear.
            %       For angled illumination, a cosine projection factor would be needed.
            Noop = (2 * deformation * shear_mm * 1e-3) / (wavelength_nm * 1e-9); % dimensionless quantity

            % Wrap phase values into [-1, 1] by adding/subtracting 2 as needed
            iter = ceil(max(abs(Noop), [], 'all', 'omitnan'));
            for k = 1:iter
                Noop(Noop > 1) = Noop(Noop > 1) - 2;
                Noop(Noop < -1) = Noop(Noop < -1) + 2;
            end
        
            PhaseShift = Noop;
            
            % Select title language for plotting
            switch lower(obj.plot_language)
                case 'de'
                    titleText = titleStr_de;
                otherwise
                    titleText = titleStr_en;
            end
            % Visualize and save the phase shift figure using grayscale colormap
            obj.plotAndSaveFigure(PhaseShift, [-1, 1], titleText, filename_base, fullfile(obj.session_folder, "figures"),'useGrayscale');

        end
  
    end
end
