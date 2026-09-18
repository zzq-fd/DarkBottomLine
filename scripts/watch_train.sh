#!/bin/bash
# Watchdog for the per-masspoint DNN training.
#
# Every CHECK_INTERVAL seconds it checks whether the training process is alive:
#   - alive -> reset the consecutive-stop counter
#   - dead  -> if this is already the 2nd consecutive stop, give up (exit);
#              otherwise wait CHECK_INTERVAL seconds and restart the training
#
# The training script skips mass points that already have a dnn_model.pt, so a
# restart resumes from where it left off.  If the training log shows it
# finished normally, the watchdog stops without restarting.

set -u

CHECK_INTERVAL=300          # seconds between checks (5 min)
REPO_DIR="/home/zzq/DarkBottomLine"
TRAIN_LOG="/tmp/train_per_masspoint.log"
WATCH_LOG="/tmp/watch_train.log"
PROC_PATTERN="train_per_masspoint.py"

TRAIN_CMD="source /home/zzq/miniconda3/etc/profile.d/conda.sh && conda activate darkbottomline && export LD_LIBRARY_PATH=/home/zzq/miniconda3/envs/darkbottomline/lib:\$LD_LIBRARY_PATH && cd ${REPO_DIR} && python scripts/train_per_masspoint.py --dnn-config configs/dnn.yaml --input /home/zzq/eventsel-merged --weight-branch full_event_weight --xsection-signal-json data/cross-section/xsection_signal.json --xsection-json data/cross-section/xsection_background_run3.json --outdir-base data/dnn_masspoint --plot-dir-base outputs/dnn_masspoint --bkg-fraction 0.25"

log_msg() { echo "$(date '+%Y-%m-%d %H:%M:%S') - $*" >> "$WATCH_LOG"; }

training_finished() {
    [ -f "$TRAIN_LOG" ] && grep -qa "Done. Trained" "$TRAIN_LOG"
}

start_training() {
    log_msg "restarting training (log: ${TRAIN_LOG})"
    nohup bash -c "$TRAIN_CMD" >> "$TRAIN_LOG" 2>&1 &
    sleep 5
}

consecutive_stops=0
log_msg "watchdog started (check every ${CHECK_INTERVAL}s; give up after 2 consecutive stops)"

while true; do
    sleep "$CHECK_INTERVAL"

    if training_finished; then
        log_msg "training finished normally - watchdog exiting"
        break
    fi

    if pgrep -f "$PROC_PATTERN" > /dev/null 2>&1; then
        if [ "$consecutive_stops" -ne 0 ]; then
            log_msg "training is running again (stop counter reset)"
        fi
        consecutive_stops=0
        continue
    fi

    consecutive_stops=$((consecutive_stops + 1))
    log_msg "training not running (consecutive stop #${consecutive_stops})"

    if [ "$consecutive_stops" -ge 2 ]; then
        log_msg "stopped 2 times in a row - giving up, no further restarts"
        break
    fi

    log_msg "waiting ${CHECK_INTERVAL}s before restart"
    sleep "$CHECK_INTERVAL"
    start_training
done
