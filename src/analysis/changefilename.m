% Script to rename .meas8625 files to .txt with angular names
clear; clc;

% Base directory containing all test folders
base_dir = fullfile(pwd, 'motor_1');

% Build folder list
fields = [0, 50, 100, 150, 200];
folders = {};
for d = fields
    folders{end+1} = sprintf('mot_1_rep_2_%dmt_off', d);
    folders{end+1} = sprintf('mot_1_rep_2_%dmt_on',  d);
end

% Angles for the 37 files (every 10 degrees, 0 to 360)
angles = 0:10:360;

if length(angles) ~= 37
    error('Angle array length must be 37, got %d', length(angles));
end

% Loop through all folders
for i = 1:length(folders)
    folder_path = fullfile(base_dir, folders{i});  

    if ~isfolder(folder_path)
        fprintf('Folder not found, skipping: %s\n', folder_path);
        continue;
    end

    fprintf('Processing folder: %s\n', folders{i});

    % Find all .meas8625 files
    files = dir(fullfile(folder_path, '*.meas8625'));

    if length(files) ~= 37
        fprintf('WARNING: Found %d files in %s, expected 37. Skipping.\n', ...
                length(files), folders{i});
        continue;
    end

    % Sort by filename (HH_MM_SS_mmm → alphabetical = chronological)
    [~, idx] = sort({files.name});
    files = files(idx);

    % Rename each file
    for j = 1:length(files)
        old_name = fullfile(folder_path, files(j).name);
        new_name = fullfile(folder_path, sprintf('torque_%ddeg.txt', angles(j)));

        try
            movefile(old_name, new_name);
            fprintf('  Renamed: %s -> torque_%ddeg.txt\n', files(j).name, angles(j));
        catch ME
            fprintf('  ERROR renaming %s: %s\n', files(j).name, ME.message);
        end
    end

    fprintf('Done: %s\n\n', folders{i});
end

fprintf('All folders processed.\n');
