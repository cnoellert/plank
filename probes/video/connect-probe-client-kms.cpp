#include <algorithm>
#include <atomic>
#include <cerrno>
#include <condition_variable>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <deque>
#include <fcntl.h>
#include <iomanip>
#include <iostream>
#include <iterator>
#include <mutex>
#include <poll.h>
#include <string>
#include <sys/stat.h>
#include <thread>
#include <time.h>
#include <unistd.h>
#include <vector>

#include <drm.h>
#include <drm_fourcc.h>
#include <gst/allocators/gstdmabuf.h>
#include <gst/app/gstappsink.h>
#include <gst/gst.h>
#include <gst/video/gstvideometa.h>
#include <xf86drm.h>
#include <xf86drmMode.h>

namespace {

struct SubmitStamp {
  std::uint64_t frame = 0;
  std::uint64_t submitted_ns = 0;
  std::uint64_t target_ns = 0;
  GstClockTime pts = GST_CLOCK_TIME_NONE;
};

struct Frame {
  GstSample* sample = nullptr;
  std::uint32_t framebuffer = 0;
};

struct CachedFramebuffer {
  dev_t device = 0;
  ino_t inode = 0;
  std::uint32_t framebuffer = 0;
  std::uint32_t gem_handle = 0;
};

struct FlipEvent {
  bool done = false;
  std::uint64_t time_ns = 0;
};

struct State {
  int drm_fd = -1;
  std::uint32_t connector_id = 0;
  std::uint32_t crtc_id = 0;
  int crtc_index = 0;
  drmModeModeInfo mode{};
  std::uint64_t refresh_ns = 16666667;
  std::uint64_t first_target_ns = 0;
  std::uint64_t steady_first_target_ns = 0;
  std::uint64_t submit_lead_ns = 6000000;
  std::uint64_t expected_frames = 0;
  std::atomic<std::uint64_t> submitted{0};
  std::atomic<std::uint64_t> queued{0};
  std::atomic<std::uint64_t> displayed{0};
  std::atomic<std::uint64_t> latest_present_ns{0};
  std::atomic<bool> failed{false};
  std::mutex submit_mutex;
  std::deque<SubmitStamp> submit_queue;
  std::mutex ready_mutex;
  std::condition_variable ready_available;
  std::condition_variable ready_consumed;
  GstSample* ready_sample = nullptr;
  SubmitStamp ready_submit;
  std::uint64_t ready_surface_ns = 0;
  bool producer_done = false;
  bool worker_stop = false;
  std::size_t max_ready_depth = 0;
  std::mutex phase_mutex;
  std::condition_variable phase_available;
  bool phase_ready = false;
  bool steady_phase_ready = false;
  Frame current;
  std::vector<CachedFramebuffer> framebuffer_cache;
  std::uint64_t framebuffer_cache_hits = 0;
  std::uint64_t framebuffer_cache_misses = 0;
  std::uint64_t stale_frames_dropped = 0;
  std::string drm_format;
  std::vector<double> decode_ms;
  std::vector<double> surface_to_flip_ms;
  std::vector<double> surface_to_worker_ms;
  std::vector<double> framebuffer_lookup_ms;
  std::vector<double> flip_event_delivery_ms;
  std::vector<double> submit_to_present_ms;
  std::vector<double> presentation_interval_ms;
  std::vector<double> input_schedule_late_ms;
  std::vector<double> flip_vs_target_ms;
  std::vector<double> surface_vs_target_ms;
  std::vector<double> worker_vs_target_ms;
  std::vector<double> previous_present_vs_target_ms;
  std::uint64_t first_present_ns = 0;
  std::uint64_t last_present_ns = 0;
};

std::uint64_t clock_ns() {
  timespec now{};
  if (clock_gettime(CLOCK_MONOTONIC, &now) != 0) return 0;
  return static_cast<std::uint64_t>(now.tv_sec) * 1000000000ULL + now.tv_nsec;
}

double mode_refresh_hz(const drmModeModeInfo& mode) {
  if (mode.htotal == 0 || mode.vtotal == 0) return 0.0;
  double hz = static_cast<double>(mode.clock) * 1000.0 /
              (static_cast<double>(mode.htotal) * mode.vtotal);
  if ((mode.flags & DRM_MODE_FLAG_INTERLACE) != 0U) hz *= 2.0;
  if ((mode.flags & DRM_MODE_FLAG_DBLSCAN) != 0U) hz /= 2.0;
  if (mode.vscan > 1) hz /= mode.vscan;
  return hz;
}

bool better_mode(const drmModeModeInfo& candidate,
                 const drmModeModeInfo& best) {
  const std::uint64_t candidate_area =
      static_cast<std::uint64_t>(candidate.hdisplay) * candidate.vdisplay;
  const std::uint64_t best_area =
      static_cast<std::uint64_t>(best.hdisplay) * best.vdisplay;
  if (candidate_area != best_area) return candidate_area > best_area;
  const bool candidate_preferred =
      (candidate.type & DRM_MODE_TYPE_PREFERRED) != 0U;
  const bool best_preferred = (best.type & DRM_MODE_TYPE_PREFERRED) != 0U;
  if (candidate_preferred != best_preferred) return candidate_preferred;
  return mode_refresh_hz(candidate) > mode_refresh_hz(best);
}

bool select_output(State* state) {
  drmModeRes* resources = drmModeGetResources(state->drm_fd);
  if (resources == nullptr) return false;
  bool found = false;
  for (int connector_index = 0; connector_index < resources->count_connectors;
       ++connector_index) {
    drmModeConnector* connector =
        drmModeGetConnector(state->drm_fd,
                            resources->connectors[connector_index]);
    if (connector == nullptr || connector->connection != DRM_MODE_CONNECTED ||
        connector->count_modes == 0) {
      drmModeFreeConnector(connector);
      continue;
    }
    drmModeEncoder* encoder = connector->encoder_id == 0
                                  ? nullptr
                                  : drmModeGetEncoder(state->drm_fd,
                                                      connector->encoder_id);
    int selected_crtc = -1;
    if (encoder != nullptr && encoder->crtc_id != 0) {
      for (int index = 0; index < resources->count_crtcs; ++index) {
        if (resources->crtcs[index] == encoder->crtc_id) selected_crtc = index;
      }
    }
    if (selected_crtc < 0 && encoder != nullptr) {
      for (int index = 0; index < resources->count_crtcs; ++index) {
        if ((encoder->possible_crtcs & (1U << index)) != 0U) {
          selected_crtc = index;
          break;
        }
      }
    }
    drmModeFreeEncoder(encoder);
    if (selected_crtc < 0) {
      drmModeFreeConnector(connector);
      continue;
    }
    drmModeModeInfo best = connector->modes[0];
    for (int index = 1; index < connector->count_modes; ++index) {
      if (better_mode(connector->modes[index], best)) {
        best = connector->modes[index];
      }
    }
    if (!found || better_mode(best, state->mode)) {
      state->connector_id = connector->connector_id;
      state->crtc_index = selected_crtc;
      state->crtc_id = resources->crtcs[selected_crtc];
      state->mode = best;
      found = true;
    }
    drmModeFreeConnector(connector);
  }
  drmModeFreeResources(resources);
  if (!found) return false;
  const double hz = mode_refresh_hz(state->mode);
  if (hz < 59.0 || hz > 61.0) return false;
  state->refresh_ns = static_cast<std::uint64_t>(1000000000.0 / hz + 0.5);
  return true;
}

void release_frame(State* state, Frame* frame) {
  (void)state;
  frame->framebuffer = 0;
  if (frame->sample != nullptr) {
    gst_sample_unref(frame->sample);
    frame->sample = nullptr;
  }
}

void release_framebuffer_cache(State* state) {
  for (const CachedFramebuffer& cached : state->framebuffer_cache) {
    if (cached.framebuffer != 0)
      drmModeRmFB(state->drm_fd, cached.framebuffer);
    if (cached.gem_handle != 0) {
      drm_gem_close close_request{};
      close_request.handle = cached.gem_handle;
      drmIoctl(state->drm_fd, DRM_IOCTL_GEM_CLOSE, &close_request);
    }
  }
  state->framebuffer_cache.clear();
}

bool parse_modifier(const char* drm_format, std::uint64_t* modifier) {
  const char* separator = std::strchr(drm_format, ':');
  if (separator == nullptr) return false;
  char* end = nullptr;
  const std::uint64_t parsed = std::strtoull(separator + 1, &end, 0);
  if (end == separator + 1 || *end != '\0') return false;
  *modifier = parsed;
  return true;
}

bool create_frame(State* state, GstSample* sample, Frame* frame) {
  GstBuffer* buffer = gst_sample_get_buffer(sample);
  GstCaps* caps = gst_sample_get_caps(sample);
  GstVideoMeta* meta =
      buffer == nullptr ? nullptr : gst_buffer_get_video_meta(buffer);
  const GstStructure* structure =
      caps == nullptr ? nullptr : gst_caps_get_structure(caps, 0);
  const gchar* drm_format =
      structure == nullptr ? nullptr
                           : gst_structure_get_string(structure, "drm-format");
  std::uint64_t modifier = 0;
  if (buffer == nullptr || meta == nullptr || drm_format == nullptr ||
      std::string(drm_format).rfind("Y410", 0) != 0 ||
      gst_buffer_n_memory(buffer) != 1 ||
      meta->width != state->mode.hdisplay ||
      meta->height != state->mode.vdisplay ||
      !parse_modifier(drm_format, &modifier)) {
    return false;
  }
  GstMemory* memory = gst_buffer_peek_memory(buffer, 0);
  if (!gst_is_dmabuf_memory(memory)) return false;
  const int dma_buf_fd = gst_dmabuf_memory_get_fd(memory);
  struct stat dma_buf_stat {};
  if (dma_buf_fd < 0 || fstat(dma_buf_fd, &dma_buf_stat) != 0) {
    return false;
  }
  const auto cached = std::find_if(
      state->framebuffer_cache.begin(), state->framebuffer_cache.end(),
      [&dma_buf_stat](const CachedFramebuffer& candidate) {
        return candidate.device == dma_buf_stat.st_dev &&
               candidate.inode == dma_buf_stat.st_ino;
      });
  if (cached != state->framebuffer_cache.end()) {
    frame->sample = sample;
    frame->framebuffer = cached->framebuffer;
    ++state->framebuffer_cache_hits;
    return true;
  }

  CachedFramebuffer new_cache_entry;
  new_cache_entry.device = dma_buf_stat.st_dev;
  new_cache_entry.inode = dma_buf_stat.st_ino;
  if (drmPrimeFDToHandle(state->drm_fd, dma_buf_fd,
                         &new_cache_entry.gem_handle) != 0) {
    return false;
  }
  const std::uint32_t handles[4] = {new_cache_entry.gem_handle, 0, 0, 0};
  const std::uint32_t pitches[4] = {
      static_cast<std::uint32_t>(meta->stride[0]), 0, 0, 0};
  const std::uint32_t offsets[4] = {
      static_cast<std::uint32_t>(meta->offset[0]), 0, 0, 0};
  const std::uint64_t modifiers[4] = {modifier, 0, 0, 0};
  if (drmModeAddFB2WithModifiers(
          state->drm_fd, meta->width, meta->height, DRM_FORMAT_XRGB2101010,
          handles, pitches, offsets, modifiers,
          &new_cache_entry.framebuffer,
          DRM_MODE_FB_MODIFIERS) != 0) {
    drm_gem_close close_request{};
    close_request.handle = new_cache_entry.gem_handle;
    drmIoctl(state->drm_fd, DRM_IOCTL_GEM_CLOSE, &close_request);
    return false;
  }
  frame->framebuffer = new_cache_entry.framebuffer;
  frame->sample = sample;
  state->framebuffer_cache.push_back(new_cache_entry);
  ++state->framebuffer_cache_misses;
  state->drm_format = drm_format;
  return true;
}

void on_page_flip(int, unsigned int, unsigned int seconds,
                  unsigned int microseconds, void* data) {
  auto* event = static_cast<FlipEvent*>(data);
  event->time_ns = static_cast<std::uint64_t>(seconds) * 1000000000ULL +
                   static_cast<std::uint64_t>(microseconds) * 1000ULL;
  event->done = true;
}

bool wait_for_flip(State* state, FlipEvent* event) {
  drmEventContext context{};
  context.version = DRM_EVENT_CONTEXT_VERSION;
  context.page_flip_handler = on_page_flip;
  while (!event->done) {
    pollfd descriptor{state->drm_fd, POLLIN, 0};
    int status = 0;
    do {
      status = poll(&descriptor, 1, 1000);
    } while (status < 0 && errno == EINTR);
    if (status <= 0 || (descriptor.revents & POLLIN) == 0 ||
        drmHandleEvent(state->drm_fd, &context) != 0) {
      return false;
    }
  }
  return true;
}

bool establish_phase(State* state) {
  drmVBlank vblank{};
  vblank.request.type = static_cast<drmVBlankSeqType>(
      DRM_VBLANK_RELATIVE |
      (state->crtc_index << DRM_VBLANK_HIGH_CRTC_SHIFT));
  vblank.request.sequence = 1;
  if (drmWaitVBlank(state->drm_fd, &vblank) != 0) return false;
  const std::uint64_t event_ns =
      static_cast<std::uint64_t>(vblank.reply.tval_sec) * 1000000000ULL +
      static_cast<std::uint64_t>(vblank.reply.tval_usec) * 1000ULL;
  state->first_target_ns = event_ns + 120ULL * state->refresh_ns;
  return true;
}

GstPadProbeReturn on_decoder_input(GstPad*, GstPadProbeInfo* info,
                                   gpointer user_data) {
  auto* state = static_cast<State*>(user_data);
  if ((GST_PAD_PROBE_INFO_TYPE(info) & GST_PAD_PROBE_TYPE_BUFFER) == 0) {
    return GST_PAD_PROBE_OK;
  }
  GstBuffer* buffer = GST_PAD_PROBE_INFO_BUFFER(info);
  if (buffer == nullptr) return GST_PAD_PROBE_OK;
  const std::uint64_t frame = ++state->submitted;
  buffer = gst_buffer_make_writable(buffer);
  if (buffer == nullptr) {
    state->failed = true;
    return GST_PAD_PROBE_DROP;
  }
  GST_PAD_PROBE_INFO_DATA(info) = buffer;
  const GstClockTime synthetic_pts =
      gst_util_uint64_scale(frame - 1, GST_SECOND, 60);
  GST_BUFFER_PTS(buffer) = synthetic_pts;
  GST_BUFFER_DTS(buffer) = synthetic_pts;
  GST_BUFFER_DURATION(buffer) = gst_util_uint64_scale(1, GST_SECOND, 60);
  std::uint64_t target_ns = 0;
  if (frame >= 2) {
    {
      std::unique_lock<std::mutex> lock(state->phase_mutex);
      state->phase_available.wait(
          lock, [state, frame] {
            return (frame == 2 ? state->phase_ready
                               : state->steady_phase_ready) ||
                   state->failed.load();
          });
      if (state->failed.load()) return GST_PAD_PROBE_DROP;
    }
    std::uint64_t* epoch = frame == 2 ? &state->first_target_ns
                                     : &state->steady_first_target_ns;
    const std::uint64_t frame_index = frame == 2 ? 0 : frame - 3;
    target_ns = *epoch + frame_index * state->refresh_ns;
    const std::uint64_t lead_ns =
        frame == 2
            ? std::max(state->submit_lead_ns,
                       static_cast<std::uint64_t>(12000000))
                   : state->submit_lead_ns;
    std::uint64_t wake_ns = target_ns - lead_ns;
    const std::uint64_t now = clock_ns();
    if (wake_ns <= now) {
      const std::uint64_t periods = (now - wake_ns) / state->refresh_ns + 1;
      *epoch += periods * state->refresh_ns;
      target_ns += periods * state->refresh_ns;
      wake_ns += periods * state->refresh_ns;
    }
    timespec wake{};
    wake.tv_sec = static_cast<time_t>(wake_ns / 1000000000ULL);
    wake.tv_nsec = static_cast<long>(wake_ns % 1000000000ULL);
    int status = 0;
    do {
      status = clock_nanosleep(CLOCK_MONOTONIC, TIMER_ABSTIME, &wake, nullptr);
    } while (status == EINTR);
    if (status != 0) {
      state->failed = true;
      return GST_PAD_PROBE_DROP;
    }
    const std::uint64_t actual_ns = clock_ns();
    state->input_schedule_late_ms.push_back(
        actual_ns > wake_ns
            ? static_cast<double>(actual_ns - wake_ns) / 1000000.0
            : 0.0);
  }
  {
    std::lock_guard<std::mutex> lock(state->submit_mutex);
    state->submit_queue.push_back(
        {frame, clock_ns(), target_ns, synthetic_pts});
  }
  return GST_PAD_PROBE_OK;
}

gboolean on_propose_allocation(GstAppSink*, GstQuery* query, gpointer) {
  gst_query_add_allocation_meta(query, GST_VIDEO_META_API_TYPE, nullptr);
  return TRUE;
}

GstFlowReturn on_new_sample(GstAppSink* sink, gpointer user_data) {
  auto* state = static_cast<State*>(user_data);
  GstSample* sample = gst_app_sink_pull_sample(sink);
  if (sample == nullptr) return GST_FLOW_ERROR;
  const std::uint64_t surface_ready_ns = clock_ns();
  GstBuffer* output_buffer = gst_sample_get_buffer(sample);
  const GstClockTime output_pts =
      output_buffer == nullptr ? GST_CLOCK_TIME_NONE
                               : GST_BUFFER_PTS(output_buffer);
  SubmitStamp submit;
  {
    std::lock_guard<std::mutex> lock(state->submit_mutex);
    const auto matching = std::find_if(
        state->submit_queue.begin(), state->submit_queue.end(),
        [output_pts](const SubmitStamp& candidate) {
          return output_pts != GST_CLOCK_TIME_NONE &&
                 candidate.pts == output_pts;
        });
    if (matching == state->submit_queue.end()) {
      gst_sample_unref(sample);
      state->failed = true;
      return GST_FLOW_ERROR;
    }
    submit = *matching;
    state->submit_queue.erase(state->submit_queue.begin(), std::next(matching));
  }
  std::unique_lock<std::mutex> lock(state->ready_mutex);
  state->ready_consumed.wait(
      lock, [state] { return state->ready_sample == nullptr ||
                            state->worker_stop; });
  if (state->worker_stop) {
    gst_sample_unref(sample);
    return GST_FLOW_ERROR;
  }
  state->ready_sample = sample;
  state->ready_submit = submit;
  state->ready_surface_ns = surface_ready_ns;
  state->max_ready_depth = 1;
  const std::uint64_t frames = ++state->queued;
  lock.unlock();
  state->ready_available.notify_one();
  return frames >= state->expected_frames ? GST_FLOW_EOS : GST_FLOW_OK;
}

bool display_sample(State* state, GstSample* sample, const SubmitStamp& submit,
                    std::uint64_t surface_ready_ns) {
  const std::uint64_t worker_started_ns = clock_ns();
  const std::uint64_t latest_present_ns = state->latest_present_ns.load();
  if (state->current.sample != nullptr && submit.target_ns != 0 &&
      latest_present_ns + 1000000ULL >= submit.target_ns) {
    ++state->stale_frames_dropped;
    gst_sample_unref(sample);
    return true;
  }
  Frame next;
  if (!create_frame(state, sample, &next)) {
    gst_sample_unref(sample);
    return false;
  }
  const std::uint64_t framebuffer_ready_ns = clock_ns();

  if (state->current.sample == nullptr) {
    if (drmModeSetCrtc(state->drm_fd, state->crtc_id, next.framebuffer, 0, 0,
                       &state->connector_id, 1, &state->mode) != 0 ||
        !establish_phase(state)) {
      release_frame(state, &next);
      return false;
    }
    state->current = next;
    ++state->displayed;
    {
      std::lock_guard<std::mutex> lock(state->phase_mutex);
      state->phase_ready = true;
    }
    state->phase_available.notify_all();
  } else {
    FlipEvent event;
    const std::uint64_t flip_queued_ns = clock_ns();
    if (drmModePageFlip(state->drm_fd, state->crtc_id, next.framebuffer,
                        DRM_MODE_PAGE_FLIP_EVENT, &event) != 0 ||
        !wait_for_flip(state, &event) || event.time_ns < submit.submitted_ns) {
      release_frame(state, &next);
      return false;
    }
    release_frame(state, &state->current);
    state->current = next;
    state->decode_ms.push_back(
        static_cast<double>(surface_ready_ns - submit.submitted_ns) /
        1000000.0);
    state->surface_to_flip_ms.push_back(
        static_cast<double>(flip_queued_ns - surface_ready_ns) / 1000000.0);
    state->surface_to_worker_ms.push_back(
        static_cast<double>(worker_started_ns - surface_ready_ns) / 1000000.0);
    state->framebuffer_lookup_ms.push_back(
        static_cast<double>(framebuffer_ready_ns - worker_started_ns) /
        1000000.0);
    state->flip_event_delivery_ms.push_back(
        static_cast<double>(static_cast<std::int64_t>(clock_ns()) -
                            static_cast<std::int64_t>(event.time_ns)) /
        1000000.0);
    state->submit_to_present_ms.push_back(
        static_cast<double>(event.time_ns - submit.submitted_ns) / 1000000.0);
    const std::uint64_t previous_present_ns = state->last_present_ns;
    if (previous_present_ns == 0) {
      state->first_present_ns = event.time_ns;
    } else {
      state->presentation_interval_ms.push_back(
          static_cast<double>(event.time_ns - previous_present_ns) /
          1000000.0);
    }
    state->last_present_ns = event.time_ns;
    state->latest_present_ns = event.time_ns;
    if (submit.frame == 2) {
      {
        std::lock_guard<std::mutex> lock(state->phase_mutex);
        state->steady_first_target_ns = event.time_ns + state->refresh_ns;
        state->steady_phase_ready = true;
      }
      state->phase_available.notify_all();
    }
    if (submit.target_ns != 0) {
      state->surface_vs_target_ms.push_back(
          static_cast<double>(static_cast<std::int64_t>(surface_ready_ns) -
                              static_cast<std::int64_t>(submit.target_ns)) /
          1000000.0);
      state->worker_vs_target_ms.push_back(
          static_cast<double>(static_cast<std::int64_t>(worker_started_ns) -
                              static_cast<std::int64_t>(submit.target_ns)) /
          1000000.0);
      if (previous_present_ns != 0) {
        state->previous_present_vs_target_ms.push_back(
            static_cast<double>(
                static_cast<std::int64_t>(previous_present_ns) -
                static_cast<std::int64_t>(submit.target_ns)) /
            1000000.0);
      }
      state->flip_vs_target_ms.push_back(
          static_cast<double>(static_cast<std::int64_t>(event.time_ns) -
                              static_cast<std::int64_t>(submit.target_ns)) /
          1000000.0);
    }
    ++state->displayed;
  }
  return true;
}

void display_worker(State* state) {
  while (true) {
    GstSample* sample = nullptr;
    SubmitStamp submit;
    std::uint64_t surface_ready_ns = 0;
    {
      std::unique_lock<std::mutex> lock(state->ready_mutex);
      state->ready_available.wait(lock, [state] {
        return state->ready_sample != nullptr || state->producer_done ||
               state->worker_stop;
      });
      if (state->worker_stop) {
        sample = state->ready_sample;
        state->ready_sample = nullptr;
        lock.unlock();
        state->ready_consumed.notify_all();
        if (sample != nullptr) gst_sample_unref(sample);
        return;
      }
      if (state->ready_sample == nullptr && state->producer_done) return;
      sample = state->ready_sample;
      submit = state->ready_submit;
      surface_ready_ns = state->ready_surface_ns;
      state->ready_sample = nullptr;
    }
    state->ready_consumed.notify_one();
    if (!display_sample(state, sample, submit, surface_ready_ns)) {
      state->failed = true;
      state->phase_available.notify_all();
      {
        std::lock_guard<std::mutex> lock(state->ready_mutex);
        state->worker_stop = true;
      }
      state->ready_available.notify_all();
      state->ready_consumed.notify_all();
      return;
    }
  }
}

double percentile(std::vector<double> values, double fraction) {
  if (values.empty()) return 0.0;
  std::sort(values.begin(), values.end());
  const std::size_t index = static_cast<std::size_t>(
      fraction * static_cast<double>(values.size() - 1));
  return values[index];
}

void print_stats(const char* name, const std::vector<double>& values) {
  std::cout << name << "_p50_ms=" << percentile(values, 0.50) << '\n'
            << name << "_p95_ms=" << percentile(values, 0.95) << '\n'
            << name << "_p99_ms=" << percentile(values, 0.99) << '\n';
}

bool parse_positive(const char* text, std::uint64_t* value) {
  char* end = nullptr;
  const unsigned long long parsed = std::strtoull(text, &end, 10);
  if (end == text || *end != '\0' || parsed == 0) return false;
  *value = parsed;
  return true;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2 || argc > 5) {
    std::cerr << "usage: " << argv[0]
              << " BITSTREAM [FRAME_COUNT] [SUBMIT_LEAD_US] [DRM_DEVICE]\n";
    return 2;
  }
  State state;
  state.expected_frames = 600;
  if (argc >= 3 && !parse_positive(argv[2], &state.expected_frames)) return 2;
  if (argc >= 4) {
    std::uint64_t lead_us = 0;
    if (!parse_positive(argv[3], &lead_us) || lead_us >= 16667) return 2;
    state.submit_lead_ns = lead_us * 1000ULL;
  }
  const char* drm_device = argc == 5 ? argv[4] : "/dev/dri/card1";
  state.drm_fd = open(drm_device, O_RDWR | O_CLOEXEC);
  std::uint64_t monotonic = 0;
  if (state.drm_fd < 0 || drmSetMaster(state.drm_fd) != 0 ||
      drmGetCap(state.drm_fd, DRM_CAP_TIMESTAMP_MONOTONIC, &monotonic) != 0 ||
      monotonic != 1 || !select_output(&state)) {
    std::cerr << "DRM initialization failed: " << std::strerror(errno) << '\n';
    if (state.drm_fd >= 0) close(state.drm_fd);
    return 3;
  }

  gst_init(&argc, &argv);
  const gchar* description =
      "filesrc name=input ! h265parse name=parser ! "
      "video/x-h265,stream-format=byte-stream,alignment=au ! vah265dec ! "
      "video/x-raw(memory:DMABuf) ! appsink name=dmabuf_sink";
  GError* error = nullptr;
  GstElement* pipeline = gst_parse_launch(description, &error);
  if (pipeline == nullptr || error != nullptr) {
    if (error != nullptr) std::cerr << error->message << '\n';
    g_clear_error(&error);
    drmDropMaster(state.drm_fd);
    close(state.drm_fd);
    return 4;
  }
  GstElement* source = gst_bin_get_by_name(GST_BIN(pipeline), "input");
  GstElement* parser = gst_bin_get_by_name(GST_BIN(pipeline), "parser");
  GstElement* sink = gst_bin_get_by_name(GST_BIN(pipeline), "dmabuf_sink");
  GstPad* parser_src =
      parser == nullptr ? nullptr : gst_element_get_static_pad(parser, "src");
  if (source == nullptr || parser == nullptr || sink == nullptr ||
      parser_src == nullptr) {
    gst_object_unref(pipeline);
    drmDropMaster(state.drm_fd);
    close(state.drm_fd);
    return 4;
  }
  g_object_set(source, "location", argv[1], nullptr);
  g_object_set(sink, "emit-signals", TRUE, "sync", FALSE, "max-buffers", 1U,
               nullptr);
  gst_pad_add_probe(parser_src, GST_PAD_PROBE_TYPE_BUFFER, on_decoder_input,
                    &state, nullptr);
  g_signal_connect(sink, "propose-allocation",
                   G_CALLBACK(on_propose_allocation), &state);
  g_signal_connect(sink, "new-sample", G_CALLBACK(on_new_sample), &state);
  gst_object_unref(source);
  gst_object_unref(parser);
  gst_object_unref(parser_src);

  std::thread worker(display_worker, &state);
  bool reached_eos =
      gst_element_set_state(pipeline, GST_STATE_PLAYING) !=
      GST_STATE_CHANGE_FAILURE;
  GstBus* bus = gst_element_get_bus(pipeline);
  GstMessage* message = reached_eos
                            ? gst_bus_timed_pop_filtered(
                                  bus, GST_CLOCK_TIME_NONE,
                                  static_cast<GstMessageType>(
                                      GST_MESSAGE_ERROR | GST_MESSAGE_EOS))
                            : nullptr;
  if (message == nullptr || GST_MESSAGE_TYPE(message) == GST_MESSAGE_ERROR) {
    reached_eos = false;
    if (message != nullptr) {
      GError* pipeline_error = nullptr;
      gchar* debug = nullptr;
      gst_message_parse_error(message, &pipeline_error, &debug);
      std::cerr << "pipeline failed: " << pipeline_error->message << '\n';
      if (debug != nullptr) std::cerr << debug << '\n';
      g_clear_error(&pipeline_error);
      g_free(debug);
    }
  }
  if (message != nullptr) gst_message_unref(message);
  {
    std::lock_guard<std::mutex> lock(state.ready_mutex);
    state.producer_done = true;
    if (!reached_eos) state.worker_stop = true;
  }
  state.ready_available.notify_all();
  state.ready_consumed.notify_all();
  worker.join();
  gst_element_set_state(pipeline, GST_STATE_NULL);
  gst_object_unref(bus);
  gst_object_unref(sink);
  gst_object_unref(pipeline);

  drmModeSetCrtc(state.drm_fd, state.crtc_id, 0, 0, 0, nullptr, 0, nullptr);
  release_frame(&state, &state.current);
  release_framebuffer_cache(&state);
  drmDropMaster(state.drm_fd);
  close(state.drm_fd);

  const std::uint64_t measured = state.submit_to_present_ms.size();
  const double effective_fps =
      measured > 1 && state.last_present_ns > state.first_present_ns
          ? static_cast<double>(measured - 1) * 1000000000.0 /
                static_cast<double>(state.last_present_ns -
                                    state.first_present_ns)
          : 0.0;
  const std::uint64_t missed = static_cast<std::uint64_t>(std::count_if(
      state.presentation_interval_ms.begin(),
      state.presentation_interval_ms.end(), [&state](double ms) {
        return ms * 1000000.0 > static_cast<double>(state.refresh_ns) * 1.5;
      }));
  const bool pacing_passed =
      reached_eos && !state.failed.load() &&
      state.displayed.load() == state.expected_frames &&
      measured + 1 == state.expected_frames && effective_fps >= 59.9 &&
      missed == 0 && state.stale_frames_dropped == 0;
  const bool latency_passed =
      percentile(state.submit_to_present_ms, 0.95) <= 8.0;
  const bool passed = pacing_passed && latency_passed;
  std::cout << std::fixed << std::setprecision(3)
            << "frames_submitted=" << state.submitted.load() << '\n'
            << "frames_queued=" << state.queued.load() << '\n'
            << "frames_displayed=" << state.displayed.load() << '\n'
            << "stale_frames_dropped=" << state.stale_frames_dropped << '\n'
            << "frames_measured=" << measured << '\n'
            << "max_ready_depth=" << state.max_ready_depth << '\n'
            << "framebuffer_cache_hits=" << state.framebuffer_cache_hits
            << '\n'
            << "framebuffer_cache_misses=" << state.framebuffer_cache_misses
            << '\n'
            << "connector_id=" << state.connector_id << '\n'
            << "crtc_id=" << state.crtc_id << '\n'
            << "mode=" << state.mode.hdisplay << 'x' << state.mode.vdisplay
            << '@' << mode_refresh_hz(state.mode) << '\n'
            << "refresh_ns=" << state.refresh_ns << '\n'
            << "submit_lead_us=" << state.submit_lead_ns / 1000ULL << '\n'
            << "decoded_drm_format=" << state.drm_format << '\n';
  print_stats("decode", state.decode_ms);
  print_stats("surface_to_flip", state.surface_to_flip_ms);
  print_stats("surface_to_worker", state.surface_to_worker_ms);
  print_stats("framebuffer_lookup", state.framebuffer_lookup_ms);
  print_stats("flip_event_delivery", state.flip_event_delivery_ms);
  print_stats("submit_to_present", state.submit_to_present_ms);
  print_stats("presentation_interval", state.presentation_interval_ms);
  print_stats("input_schedule_late", state.input_schedule_late_ms);
  print_stats("flip_vs_target", state.flip_vs_target_ms);
  print_stats("surface_vs_target", state.surface_vs_target_ms);
  print_stats("worker_vs_target", state.worker_vs_target_ms);
  print_stats("previous_present_vs_target",
              state.previous_present_vs_target_ms);
  std::cout << "effective_presentation_fps=" << effective_fps << '\n'
            << "missed_refresh_intervals=" << missed << '\n'
            << "decoded_surface_cpu_map=no\n"
            << "direct_kms_60hz_gate="
            << (pacing_passed ? "pass" : "fail") << '\n'
            << "direct_kms_8ms_gate="
            << (latency_passed ? "pass" : "fail") << '\n'
            << "direct_kms_gate=" << (passed ? "pass" : "fail") << '\n';
  return passed ? 0 : 1;
}
