cmake_minimum_required(VERSION 3.20)

project(stationconnect_qualification VERSION 0.1.0 LANGUAGES C CXX)

include(CTest)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(LIBDRM REQUIRED IMPORTED_TARGET libdrm)
pkg_check_modules(SYSTEMD REQUIRED IMPORTED_TARGET libsystemd)
pkg_check_modules(EGL REQUIRED IMPORTED_TARGET egl)
pkg_check_modules(GBM QUIET IMPORTED_TARGET gbm)
pkg_check_modules(GLESV2 QUIET IMPORTED_TARGET glesv2)
pkg_check_modules(WAYLAND QUIET IMPORTED_TARGET wayland-client wayland-egl)
pkg_check_modules(GSTREAMER QUIET IMPORTED_TARGET
  gstreamer-1.0
  gstreamer-app-1.0
  gstreamer-video-1.0
  gstreamer-allocators-1.0)
find_path(FFNVCODEC_INCLUDE_DIR ffnvcodec/nvEncodeAPI.h REQUIRED)
set(NVFBC_SDK_ROOT "" CACHE PATH "Path to the NVIDIA Capture SDK root")
find_path(NVFBC_INCLUDE_DIR NvFBC.h
  HINTS
    "${NVFBC_SDK_ROOT}"
    "$ENV{NVFBC_SDK_ROOT}"
    "${CMAKE_CURRENT_SOURCE_DIR}/../nvidia/Capture_Linux_v9.0.0/NvFBC"
  PATH_SUFFIXES NvFBC/inc inc)
find_path(PAM_INCLUDE_DIR security/pam_appl.h REQUIRED)
find_library(PAM_LIBRARY pam REQUIRED)
set(X264_ROOT "" CACHE PATH "Path to an x264 installation")
find_path(X264_INCLUDE_DIR x264.h
  HINTS "${X264_ROOT}" "${CMAKE_CURRENT_SOURCE_DIR}/build/third-party/prefix"
  PATH_SUFFIXES include)
find_library(X264_LIBRARY x264
  HINTS "${X264_ROOT}" "${CMAKE_CURRENT_SOURCE_DIR}/build/third-party/prefix"
  PATH_SUFFIXES lib lib64)

add_executable(connect-probe-kms probes/kms/connect-probe-kms.cpp)
target_compile_features(connect-probe-kms PRIVATE cxx_std_17)
target_compile_options(connect-probe-kms PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(connect-probe-kms PRIVATE PkgConfig::LIBDRM)

add_library(stationconnect-session-context STATIC
  host/sunshine-fork/src/session/session_context.cpp)
target_compile_features(stationconnect-session-context PRIVATE cxx_std_20)
target_compile_options(stationconnect-session-context PRIVATE
  -Wall -Wextra -Wpedantic -Werror)
target_include_directories(stationconnect-session-context PUBLIC
  host/sunshine-fork/src)
target_link_libraries(stationconnect-session-context PUBLIC PkgConfig::SYSTEMD)

add_executable(connect-probe-kms-xb30 probes/kms/connect-probe-kms-xb30.cpp)
target_compile_features(connect-probe-kms-xb30 PRIVATE cxx_std_17)
target_compile_options(connect-probe-kms-xb30 PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(connect-probe-kms-xb30 PRIVATE PkgConfig::LIBDRM PkgConfig::EGL)

if(GSTREAMER_FOUND AND GBM_FOUND AND GLESV2_FOUND)
  add_executable(connect-probe-vaapi-dmabuf
    probes/video/connect-probe-vaapi-dmabuf.cpp)
  target_compile_features(connect-probe-vaapi-dmabuf PRIVATE cxx_std_17)
  target_compile_options(connect-probe-vaapi-dmabuf PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(connect-probe-vaapi-dmabuf PRIVATE
    PkgConfig::GSTREAMER PkgConfig::EGL PkgConfig::GBM PkgConfig::GLESV2
    PkgConfig::LIBDRM)
endif()

if(GSTREAMER_FOUND)
  add_executable(connect-probe-client-kms
    probes/video/connect-probe-client-kms.cpp)
  target_compile_features(connect-probe-client-kms PRIVATE cxx_std_17)
  target_compile_options(connect-probe-client-kms PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(connect-probe-client-kms PRIVATE
    PkgConfig::GSTREAMER PkgConfig::LIBDRM)
endif()

find_program(WAYLAND_SCANNER wayland-scanner)
pkg_get_variable(WAYLAND_PROTOCOLS_DATA wayland-protocols pkgdatadir)
set(XDG_SHELL_XML
  "${WAYLAND_PROTOCOLS_DATA}/stable/xdg-shell/xdg-shell.xml")
set(PRESENTATION_TIME_XML
  "${WAYLAND_PROTOCOLS_DATA}/stable/presentation-time/presentation-time.xml")
set(COMMIT_TIMING_XML
  "${WAYLAND_PROTOCOLS_DATA}/staging/commit-timing/commit-timing-v1.xml")
set(FIFO_XML "${WAYLAND_PROTOCOLS_DATA}/staging/fifo/fifo-v1.xml")
if(WAYLAND_FOUND AND GLESV2_FOUND AND WAYLAND_SCANNER AND
   EXISTS "${XDG_SHELL_XML}")
  set(XDG_SHELL_HEADER "${CMAKE_CURRENT_BINARY_DIR}/xdg-shell-client-protocol.h")
  set(XDG_SHELL_CODE "${CMAKE_CURRENT_BINARY_DIR}/xdg-shell-protocol.c")
  add_custom_command(
    OUTPUT "${XDG_SHELL_HEADER}" "${XDG_SHELL_CODE}"
    COMMAND "${WAYLAND_SCANNER}" client-header "${XDG_SHELL_XML}" "${XDG_SHELL_HEADER}"
    COMMAND "${WAYLAND_SCANNER}" private-code "${XDG_SHELL_XML}" "${XDG_SHELL_CODE}"
    DEPENDS "${XDG_SHELL_XML}")
  add_executable(connect-probe-wayland-xr30
    probes/video/connect-probe-wayland-xr30.cpp
    "${XDG_SHELL_CODE}" "${XDG_SHELL_HEADER}")
  target_compile_features(connect-probe-wayland-xr30 PRIVATE cxx_std_17)
  target_compile_options(connect-probe-wayland-xr30 PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(connect-probe-wayland-xr30 PRIVATE
    "${CMAKE_CURRENT_BINARY_DIR}")
  target_link_libraries(connect-probe-wayland-xr30 PRIVATE
    PkgConfig::WAYLAND PkgConfig::EGL PkgConfig::GLESV2 PkgConfig::LIBDRM)

  if(GSTREAMER_FOUND AND EXISTS "${PRESENTATION_TIME_XML}")
    set(PRESENTATION_TIME_HEADER
      "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-client-protocol.h")
    set(PRESENTATION_TIME_CODE
      "${CMAKE_CURRENT_BINARY_DIR}/presentation-time-protocol.c")
    add_custom_command(
      OUTPUT "${PRESENTATION_TIME_HEADER}" "${PRESENTATION_TIME_CODE}"
      COMMAND "${WAYLAND_SCANNER}" client-header "${PRESENTATION_TIME_XML}"
        "${PRESENTATION_TIME_HEADER}"
      COMMAND "${WAYLAND_SCANNER}" private-code "${PRESENTATION_TIME_XML}"
        "${PRESENTATION_TIME_CODE}"
      DEPENDS "${PRESENTATION_TIME_XML}")
    add_executable(connect-probe-client-pipeline
      probes/video/connect-probe-client-pipeline.cpp
      "${XDG_SHELL_CODE}" "${XDG_SHELL_HEADER}"
      "${PRESENTATION_TIME_CODE}" "${PRESENTATION_TIME_HEADER}")
    if(EXISTS "${COMMIT_TIMING_XML}")
      set(COMMIT_TIMING_HEADER
        "${CMAKE_CURRENT_BINARY_DIR}/commit-timing-v1-client-protocol.h")
      set(COMMIT_TIMING_CODE
        "${CMAKE_CURRENT_BINARY_DIR}/commit-timing-v1-protocol.c")
      add_custom_command(
        OUTPUT "${COMMIT_TIMING_HEADER}" "${COMMIT_TIMING_CODE}"
        COMMAND "${WAYLAND_SCANNER}" client-header "${COMMIT_TIMING_XML}"
          "${COMMIT_TIMING_HEADER}"
        COMMAND "${WAYLAND_SCANNER}" private-code "${COMMIT_TIMING_XML}"
          "${COMMIT_TIMING_CODE}"
        DEPENDS "${COMMIT_TIMING_XML}")
      target_sources(connect-probe-client-pipeline PRIVATE
        "${COMMIT_TIMING_CODE}" "${COMMIT_TIMING_HEADER}")
      target_compile_definitions(connect-probe-client-pipeline PRIVATE
        CONNECT_HAVE_COMMIT_TIMING=1)
    endif()
    if(EXISTS "${FIFO_XML}")
      set(FIFO_HEADER "${CMAKE_CURRENT_BINARY_DIR}/fifo-v1-client-protocol.h")
      set(FIFO_CODE "${CMAKE_CURRENT_BINARY_DIR}/fifo-v1-protocol.c")
      add_custom_command(
        OUTPUT "${FIFO_HEADER}" "${FIFO_CODE}"
        COMMAND "${WAYLAND_SCANNER}" client-header "${FIFO_XML}"
          "${FIFO_HEADER}"
        COMMAND "${WAYLAND_SCANNER}" private-code "${FIFO_XML}"
          "${FIFO_CODE}"
        DEPENDS "${FIFO_XML}")
      target_sources(connect-probe-client-pipeline PRIVATE
        "${FIFO_CODE}" "${FIFO_HEADER}")
      target_compile_definitions(connect-probe-client-pipeline PRIVATE
        CONNECT_HAVE_FIFO=1)
    endif()
    target_compile_features(connect-probe-client-pipeline PRIVATE cxx_std_17)
    target_compile_options(connect-probe-client-pipeline PRIVATE
      -Wall -Wextra -Wpedantic -Werror)
    target_include_directories(connect-probe-client-pipeline PRIVATE
      "${CMAKE_CURRENT_BINARY_DIR}")
    target_link_libraries(connect-probe-client-pipeline PRIVATE
      PkgConfig::GSTREAMER PkgConfig::WAYLAND PkgConfig::EGL
      PkgConfig::GLESV2 PkgConfig::LIBDRM Threads::Threads)
  endif()
endif()

add_executable(connect-probe-nvenc probes/nvenc/connect-probe-nvenc.cpp)
target_compile_features(connect-probe-nvenc PRIVATE cxx_std_17)
target_compile_options(connect-probe-nvenc PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(connect-probe-nvenc PRIVATE ${FFNVCODEC_INCLUDE_DIR})
target_link_libraries(connect-probe-nvenc PRIVATE ${CMAKE_DL_LIBS})

if(X264_INCLUDE_DIR AND X264_LIBRARY)
  add_executable(connect-benchmark-x264
    probes/video/connect-benchmark-x264.cpp)
  target_compile_features(connect-benchmark-x264 PRIVATE cxx_std_17)
  target_compile_options(connect-benchmark-x264 PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(connect-benchmark-x264 PRIVATE ${X264_INCLUDE_DIR})
  target_link_libraries(connect-benchmark-x264 PRIVATE
    ${X264_LIBRARY} Threads::Threads ${CMAKE_DL_LIBS} m)
else()
  message(STATUS "x264 not found; connect-benchmark-x264 will not be built")
endif()

if(NVFBC_INCLUDE_DIR)
  add_executable(connect-probe-nvfbc probes/nvfbc/connect-probe-nvfbc.cpp)
  target_compile_features(connect-probe-nvfbc PRIVATE cxx_std_17)
  target_compile_options(connect-probe-nvfbc PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(connect-probe-nvfbc PRIVATE
    ${NVFBC_INCLUDE_DIR}
    ${FFNVCODEC_INCLUDE_DIR})
  target_link_libraries(connect-probe-nvfbc PRIVATE ${CMAKE_DL_LIBS})

  add_executable(connect-capture-nvfbc-raw
    probes/nvfbc/connect-capture-nvfbc-raw.cpp)
  target_compile_features(connect-capture-nvfbc-raw PRIVATE cxx_std_17)
  target_compile_options(connect-capture-nvfbc-raw PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(connect-capture-nvfbc-raw PRIVATE
    ${NVFBC_INCLUDE_DIR}
    ${FFNVCODEC_INCLUDE_DIR})
  target_link_libraries(connect-capture-nvfbc-raw PRIVATE ${CMAKE_DL_LIBS})

  add_executable(connect-probe-video-pipeline
    probes/video/connect-probe-video-pipeline.cpp)
  target_compile_features(connect-probe-video-pipeline PRIVATE cxx_std_17)
  target_compile_options(connect-probe-video-pipeline PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(connect-probe-video-pipeline PRIVATE
    ${NVFBC_INCLUDE_DIR}
    ${FFNVCODEC_INCLUDE_DIR})
  target_link_libraries(connect-probe-video-pipeline PRIVATE
    ${CMAKE_DL_LIBS} Threads::Threads)
else()
  message(STATUS "NvFBC SDK header not found; connect-probe-nvfbc will not be built")
endif()

add_executable(connect-probe-wacom probes/wacom/connect-probe-wacom.cpp)
target_compile_features(connect-probe-wacom PRIVATE cxx_std_17)
target_compile_options(connect-probe-wacom PRIVATE -Wall -Wextra -Wpedantic -Werror)

add_executable(connect-probe-pam probes/auth/connect-probe-pam.cpp)
target_compile_features(connect-probe-pam PRIVATE cxx_std_17)
target_compile_options(connect-probe-pam PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(connect-probe-pam PRIVATE ${PAM_INCLUDE_DIR})
target_link_libraries(connect-probe-pam PRIVATE ${PAM_LIBRARY})

add_executable(connect-probe-uhid probes/wacom/connect-probe-uhid.cpp)
target_compile_features(connect-probe-uhid PRIVATE cxx_std_17)
target_compile_options(connect-probe-uhid PRIVATE -Wall -Wextra -Wpedantic -Werror)

add_executable(connect-wacom-raw-bridge
  probes/wacom/connect-wacom-raw-bridge.cpp)
target_compile_features(connect-wacom-raw-bridge PRIVATE cxx_std_17)
target_compile_options(connect-wacom-raw-bridge PRIVATE
  -Wall -Wextra -Wpedantic -Werror)

if(BUILD_TESTING)
  add_test(NAME packaging-launchers
    COMMAND bash ${CMAKE_CURRENT_SOURCE_DIR}/tests/packaging/test-launchers.sh)
  add_test(NAME host-supervisor-package
    COMMAND bash
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/packaging/test-host-supervisor-package.sh)
  add_test(NAME host-certificate-profile
    COMMAND bash
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/packaging/test-host-certificate.sh)
  add_test(NAME host-state-profile
    COMMAND bash
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/packaging/test-host-state.sh)
  add_test(NAME display-prepare
    COMMAND bash
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/display/test-display-prepare.sh)
  add_test(NAME av-sync-telemetry-analyzer
    COMMAND bash
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/audio/test-analyze-av-sync-telemetry.sh)
  add_test(NAME host-version-discovery
    COMMAND bash
      ${CMAKE_CURRENT_SOURCE_DIR}/tests/protocol/test-host-version-discovery.sh)

  add_executable(session-policy-test tests/session/test-session-policy.cpp)
  target_compile_features(session-policy-test PRIVATE cxx_std_20)
  target_compile_options(session-policy-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(session-policy-test PRIVATE stationconnect-session-context)
  add_test(NAME session-policy COMMAND session-policy-test)

  add_executable(extended-fec-block-indices-test
    tests/protocol/extended-fec-block-indices.c)
  target_compile_options(extended-fec-block-indices-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(extended-fec-block-indices-test PRIVATE
    client/moonlight-qt-fork/moonlight-common-c/moonlight-common-c/src)
  add_test(NAME extended-fec-block-indices
    COMMAND extended-fec-block-indices-test)

  add_executable(video-packet-loss-telemetry-test
    tests/protocol/video-packet-loss-telemetry.c)
  target_compile_options(video-packet-loss-telemetry-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(video-packet-loss-telemetry-test PRIVATE
    client/moonlight-qt-fork/moonlight-common-c/moonlight-common-c/src)
  add_test(NAME video-packet-loss-telemetry
    COMMAND video-packet-loss-telemetry-test)

  add_executable(video-packet-loss-window-test
    tests/protocol/video-packet-loss-window.cpp)
  target_compile_features(video-packet-loss-window-test PRIVATE cxx_std_17)
  target_compile_options(video-packet-loss-window-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(video-packet-loss-window-test PRIVATE
    client/moonlight-qt-fork)
  add_test(NAME video-packet-loss-window
    COMMAND video-packet-loss-window-test)

  add_executable(wacom-hid-v2-test tests/protocol/wacom-hid-v2.c)
  target_compile_options(wacom-hid-v2-test PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(wacom-hid-v2-test PRIVATE
    client/moonlight-qt-fork/moonlight-common-c/moonlight-common-c/src)
  add_test(NAME wacom-hid-v2 COMMAND wacom-hid-v2-test)

  add_test(NAME kms-probe-self-test COMMAND connect-probe-kms --self-test)
  if(TARGET connect-probe-nvfbc)
    add_test(NAME nvfbc-probe-self-test COMMAND connect-probe-nvfbc --self-test)
    add_test(NAME video-pipeline-self-test
      COMMAND connect-probe-video-pipeline --self-test)
  endif()
endif()
