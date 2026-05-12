clear; clc; close all;

base_dir  = fullfile(pwd, 'motor_1');
fields_mT = [0, 50, 100, 150, 200];
angles    = 0:10:360;

% ── colours per field level, solid=ON / dashed=OFF ──────────────────────
colours = [0 0 0; 0 0.45 0.74; 0.47 0.67 0.19; 0.93 0.69 0.13; 0.85 0.33 0.10];

% ── read all data ────────────────────────────────────────────────────────
data = struct();   % data(rep, field_idx).on / .off  → 1×37 mean torque

for rep = 1:2
    for fi = 1:length(fields_mT)
        f = fields_mT(fi);

        for oo = 1:2   % 1=OFF, 2=ON
            state = {'off','on'};
            folder = sprintf('mot_1_rep_%d_%dmt_%s', rep, f, state{oo});
            folder_path = fullfile(base_dir, folder);

            torque_mean = NaN(1, length(angles));

            if ~isfolder(folder_path)
                fprintf('Not found: %s\n', folder);
            else
                for j = 1:length(angles)
                    fpath = fullfile(folder_path, sprintf('torque_%ddeg.txt', angles(j)));
                    if isfile(fpath)
                        torque_mean(j) = read_mean_torque(fpath);
                    end
                end
            end

            if oo == 1
                data(rep, fi).off = torque_mean;
            else
                data(rep, fi).on  = torque_mean;
            end
            data(rep, fi).field = f;
        end
    end
end

% ── correction: rep1 angles shifted by +90° ─────────────────────
% (motor was physically mirrored between rep1 and rep2)
for fi = 1:length(fields_mT)
    for fn = {'off','on'}
        d = data(1,fi).(fn{1});
        d = circshift(d, 9);   % shift +90°: lo 0° diventa il nuovo 90°
        d(end) = d(1);         % chiudi 0°=360°
        data(1,fi).(fn{1}) = d;
    end
end

% ── baseline subtraction: remove 0mT offset ─────────────────────────────
% 0mT OFF subtracted from all OFF curves, 0mT ON from all ON curves
for rep = 1:2
    baseline_off = data(rep, 1).off;   % fi=1 → 0mT
    baseline_on  = data(rep, 1).on;

    for fi = 1:length(fields_mT)
        data(rep, fi).off = data(rep, fi).off - baseline_off;
        data(rep, fi).on  = data(rep, fi).on  - baseline_on;
    end
end

% ── plotting ─────────────────────────────────────────────────────────────
fig_titles = {'Rep 1', 'Rep 2', 'Rep 1 & 2 — overlay'};
figs = gobjects(3,1);
for k = 1:3; figs(k) = figure('Name', fig_titles{k}, 'Position', [100+300*(k-1), 100, 800, 500]); end

for rep = 1:2
    figure(figs(rep)); hold on; grid on;
    for fi = 1:length(fields_mT)
        c   = colours(fi,:);
        lbl = sprintf('%d mT', fields_mT(fi));
        plot(angles, data(rep,fi).off, '--', 'Color', c, 'LineWidth', 1.5, ...
             'DisplayName', [lbl ' OFF']);
        plot(angles, data(rep,fi).on,  '-',  'Color', c, 'LineWidth', 1.5, ...
             'DisplayName', [lbl ' ON']);
    end
    format_plot(fig_titles{rep});
end

% overlay: rep1 thicker, rep2 thinner
figure(figs(3)); hold on; grid on;
lw = [2, 1];          % linewidth per rep
for rep = 1:2
    for fi = 1:length(fields_mT)
        c   = colours(fi,:);
        lbl = sprintf('%d mT', fields_mT(fi));
        plot(angles, data(rep,fi).off, '--', 'Color', c, 'LineWidth', lw(rep), ...
             'DisplayName', sprintf('Rep%d %s OFF', rep, lbl));
        plot(angles, data(rep,fi).on,  '-',  'Color', c, 'LineWidth', lw(rep), ...
             'DisplayName', sprintf('Rep%d %s ON',  rep, lbl));
    end
end
format_plot('Rep 1 & 2 — overlay');

% ── helpers ──────────────────────────────────────────────────────────────
function m = read_mean_torque(filepath)
    fid = fopen(filepath, 'r');
    raw = textscan(fid, '%s', 'Delimiter', '\n'); raw = raw{1};
    fclose(fid);

    i0 = find(strcmp(raw, '[MEAS]'),     1) + 1;
    i1 = find(strcmp(raw, '[SETPOINTS]'),1) - 1;

    vals = [];
    for k = i0:i1
        line = raw{k};
        % skip MIN= MAX= COUNT=
        if any(startsWith(line, {'MIN=','MAX=','COUNT='})); continue; end
        parts = strsplit(line, ';');
        if length(parts) >= 2
            v = str2double(parts{2});
            if ~isnan(v); vals(end+1) = v; end
        end
    end
    m = mean(vals);
end

function format_plot(ttl)
    xlabel('Angle [deg]',        'FontSize', 11);
    ylabel('Mean Torque [Nm]',   'FontSize', 11);
    title(ttl,                   'FontSize', 13, 'FontWeight', 'bold');
    legend('Location', 'bestoutside', 'FontSize', 9);
    xlim([0 360]);
    ylim([-0.025 0.025])
    xticks(0:30:360);
end