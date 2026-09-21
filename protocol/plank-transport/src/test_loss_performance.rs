// SPDX-License-Identifier: AGPL-3.0-or-later

//! Test-only loopback regression bounds, not WAN or glass-to-glass targets.
//! Measure from the fixed 60 Hz availability schedule, never from a delayed
//! send call: backpressure must not quietly lower the offered load or hide lag.

use std::time::Duration;

pub(super) const FRAME_RATE: u64 = 60;
pub(super) const PAYLOAD_BYTES: usize = 312_500; // Exactly 150 Mbps at 60 Hz, before FEC.
pub(super) const FRAMES_PER_PHASE: usize = 180;
pub(super) const LOSS_BASIS_POINTS: [u64; 5] = [0, 50, 100, 300, 500];
pub(super) const TOTAL_FRAMES: usize = FRAMES_PER_PHASE * LOSS_BASIS_POINTS.len();
pub(super) const MIN_PAYLOAD_BPS: u64 = 142_500_000; // 95% of nominal per phase.
pub(super) const P95_DELIVERY_LIMIT: Duration = Duration::from_millis(50);
pub(super) const FRAME_DEADLINE: Duration = Duration::from_millis(100);
pub(super) const MAX_RECEIVE_GAP: Duration = Duration::from_millis(100);

pub(super) fn frame_offset(frame: usize) -> Duration {
    Duration::from_nanos(frame as u64 * 1_000_000_000 / FRAME_RATE)
}

#[derive(Debug)]
pub(super) struct PhasePerformance {
    pub submitted_bps: u64,
    pub received_bps: u64,
    pub received_millifps: u64,
    pub submission_max: Duration,
    pub delivery_p95: Duration,
    pub delivery_max: Duration,
    pub receive_gap_max: Duration,
    pub completion: Duration,
}

impl PhasePerformance {
    pub fn measure(
        first_frame: usize,
        submitted: &[Duration],
        received: &[Duration],
        previous_receive: Option<Duration>,
    ) -> Result<Self, &'static str> {
        if submitted.len() != FRAMES_PER_PHASE || received.len() != FRAMES_PER_PHASE {
            return Err("incomplete loss phase timing samples");
        }
        let start = frame_offset(first_frame);
        let end = frame_offset(first_frame + FRAMES_PER_PHASE);
        let mut last_receive = previous_receive.unwrap_or(start);
        let mut last_submit = start;
        let mut receive_gap_max = Duration::ZERO;
        let mut submission_max = Duration::ZERO;
        let mut latency = Vec::with_capacity(FRAMES_PER_PHASE);
        for (index, (&send, &receive)) in submitted.iter().zip(received).enumerate() {
            let due = frame_offset(first_frame + index);
            if send < due || receive < due || send < last_submit || receive < last_receive {
                return Err("loss phase timing is early or non-monotonic");
            }
            latency.push(receive - due);
            submission_max = submission_max.max(send - due);
            receive_gap_max = receive_gap_max.max(receive - last_receive);
            last_receive = receive;
            last_submit = send;
        }
        // Include any end-of-phase backlog, but never credit an early final
        // frame with more than the intended 150 Mbps/60 fps offered load.
        let submit_elapsed = last_submit.max(end) - start;
        let receive_elapsed = last_receive.max(end) - start;
        let bits = FRAMES_PER_PHASE as u128 * PAYLOAD_BYTES as u128 * 8;
        let submitted_bps = (bits * 1_000_000_000 / submit_elapsed.as_nanos()) as u64;
        let received_bps = (bits * 1_000_000_000 / receive_elapsed.as_nanos()) as u64;
        let received_millifps =
            (FRAMES_PER_PHASE as u128 * 1_000_000_000_000 / receive_elapsed.as_nanos()) as u64;
        latency.sort_unstable();
        let p95_index = (latency.len() * 95).div_ceil(100) - 1;
        Ok(Self {
            submitted_bps,
            received_bps,
            received_millifps,
            submission_max,
            delivery_p95: latency[p95_index],
            delivery_max: *latency.last().unwrap(),
            receive_gap_max,
            completion: submit_elapsed.max(receive_elapsed),
        })
    }

    pub fn violations(&self) -> Vec<&'static str> {
        let mut reasons = Vec::new();
        if self.submitted_bps < MIN_PAYLOAD_BPS {
            reasons.push("sender throughput below 142.5 Mbps");
        }
        if self.received_bps < MIN_PAYLOAD_BPS {
            reasons.push("receiver throughput below 142.5 Mbps");
        }
        if self.submission_max > FRAME_DEADLINE {
            reasons.push("maximum scheduled frame submission exceeds 100 ms");
        }
        if self.delivery_p95 > P95_DELIVERY_LIMIT {
            reasons.push("p95 scheduled frame delivery exceeds 50 ms");
        }
        if self.delivery_max > FRAME_DEADLINE {
            reasons.push("maximum scheduled frame delivery exceeds 100 ms");
        }
        if self.receive_gap_max > MAX_RECEIVE_GAP {
            reasons.push("receive stall exceeds 100 ms");
        }
        reasons
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn samples(first_frame: usize, delay: Duration) -> Vec<Duration> {
        (first_frame..first_frame + FRAMES_PER_PHASE)
            .map(|frame| frame_offset(frame) + delay)
            .collect()
    }

    #[test]
    fn nominal_load_is_exact_and_passing_at_every_loss_phase() {
        assert_eq!(PAYLOAD_BYTES as u64 * FRAME_RATE * 8, 150_000_000);
        assert_eq!(frame_offset(FRAMES_PER_PHASE), Duration::from_secs(3));
        assert_eq!(TOTAL_FRAMES, 900);
        for first in (0..TOTAL_FRAMES).step_by(FRAMES_PER_PHASE) {
            let sent = samples(first, Duration::from_millis(5));
            let received = samples(first, Duration::from_millis(8));
            let previous = first
                .checked_sub(1)
                .map(|f| frame_offset(f) + Duration::from_millis(8));
            let measured = PhasePerformance::measure(first, &sent, &received, previous).unwrap();
            assert!(measured.violations().is_empty(), "{measured:?}");
            assert_eq!(measured.submitted_bps, 150_000_000);
            assert_eq!(measured.received_bps, 150_000_000);
            assert_eq!(measured.received_millifps, 60_000);
        }
    }

    #[test]
    fn slow_sender_fails_even_when_all_frames_eventually_arrive() {
        let sent: Vec<_> = (0..FRAMES_PER_PHASE)
            .map(|frame| Duration::from_millis(frame as u64 * 20 + 5))
            .collect(); // 50 fps, not 60 fps.
        let received: Vec<_> = sent.iter().map(|t| *t + Duration::from_millis(3)).collect();
        let measured = PhasePerformance::measure(0, &sent, &received, None).unwrap();
        assert!(
            measured
                .violations()
                .contains(&"sender throughput below 142.5 Mbps")
        );
        assert!(
            measured
                .violations()
                .contains(&"receiver throughput below 142.5 Mbps")
        );
    }

    #[test]
    fn a_stall_cannot_hide_behind_catch_up_and_good_average_throughput() {
        let sent = samples(0, Duration::from_millis(5));
        let mut received = samples(0, Duration::from_millis(8));
        let resumed = received[66];
        received[60..=66].fill(resumed);
        let measured = PhasePerformance::measure(0, &sent, &received, None).unwrap();
        assert_eq!(measured.received_bps, 150_000_000);
        assert!(
            measured
                .violations()
                .contains(&"receive stall exceeds 100 ms")
        );
        assert!(
            measured
                .violations()
                .contains(&"maximum scheduled frame delivery exceeds 100 ms")
        );
    }

    #[test]
    fn tail_latency_is_measured_per_phase_not_diluted_by_clean_phases() {
        let first = FRAMES_PER_PHASE * 4;
        let sent = samples(first, Duration::from_millis(5));
        let mut received = samples(first, Duration::from_millis(8));
        for timestamp in &mut received[FRAMES_PER_PHASE - 12..] {
            *timestamp += Duration::from_millis(50);
        }
        let measured = PhasePerformance::measure(first, &sent, &received, None).unwrap();
        assert_eq!(measured.delivery_p95, Duration::from_millis(58));
        assert_eq!(
            measured.violations(),
            vec!["p95 scheduled frame delivery exceeds 50 ms"]
        );
    }

    #[test]
    fn phase_boundaries_do_not_reset_the_schedule_or_hide_receive_gaps() {
        let first = FRAMES_PER_PHASE;
        let sent = samples(first, Duration::from_millis(200));
        let received = samples(first, Duration::from_millis(208));
        let previous = frame_offset(first - 1) + Duration::from_millis(8);
        let measured = PhasePerformance::measure(first, &sent, &received, Some(previous)).unwrap();
        assert!(
            measured
                .violations()
                .contains(&"receive stall exceeds 100 ms")
        );
        assert!(
            measured
                .violations()
                .contains(&"maximum scheduled frame delivery exceeds 100 ms")
        );
    }

    #[test]
    fn incomplete_or_invalid_samples_fail_instead_of_producing_a_pass() {
        let sent = samples(0, Duration::from_millis(5));
        let mut received = samples(0, Duration::from_millis(8));
        assert!(PhasePerformance::measure(0, &[], &[], None).is_err());
        assert!(PhasePerformance::measure(0, &sent, &received[1..], None).is_err());
        received.swap(1, 2);
        assert!(PhasePerformance::measure(0, &sent, &received, None).is_err());
        received = samples(0, Duration::ZERO);
        received[1] -= Duration::from_nanos(1);
        assert!(PhasePerformance::measure(0, &sent, &received, None).is_err());
    }

    #[test]
    fn late_submission_fails_even_if_the_final_frame_was_already_delivered() {
        let mut sent = samples(0, Duration::from_millis(5));
        let received = samples(0, Duration::from_millis(8));
        *sent.last_mut().unwrap() += FRAME_DEADLINE;
        let measured = PhasePerformance::measure(0, &sent, &received, None).unwrap();
        assert_eq!(
            measured.violations(),
            vec!["maximum scheduled frame submission exceeds 100 ms"]
        );
    }

    #[test]
    fn limits_are_inclusive_but_not_silently_relaxed() {
        let sent = samples(0, Duration::from_millis(5));
        let received = samples(0, Duration::from_millis(8));
        let mut measured = PhasePerformance::measure(0, &sent, &received, None).unwrap();
        measured.submitted_bps = MIN_PAYLOAD_BPS;
        measured.received_bps = MIN_PAYLOAD_BPS;
        measured.submission_max = FRAME_DEADLINE;
        measured.delivery_p95 = P95_DELIVERY_LIMIT;
        measured.delivery_max = FRAME_DEADLINE;
        measured.receive_gap_max = MAX_RECEIVE_GAP;
        assert!(measured.violations().is_empty());
        measured.submitted_bps -= 1;
        measured.received_bps -= 1;
        measured.submission_max += Duration::from_nanos(1);
        measured.delivery_p95 += Duration::from_nanos(1);
        measured.delivery_max += Duration::from_nanos(1);
        measured.receive_gap_max += Duration::from_nanos(1);
        assert_eq!(measured.violations().len(), 6);
    }
}
