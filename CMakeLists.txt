cmake_minimum_required(VERSION 3.20)

project(stationconnect_qualification VERSION 0.1.0 LANGUAGES CXX)

include(CTest)
find_package(PkgConfig REQUIRED)
find_package(Threads REQUIRED)
pkg_check_modules(LIBDRM REQUIRED IMPORTED_TARGET libdrm)
pkg_check_modules(EGL REQUIRED IMPORTED_TARGET egl)
pkg_check_modules(GBM QUIET IMPORTED_TARGET gbm)
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

add_executable(connect-probe-kms probes/kms/connect-probe-kms.cpp)
target_compile_features(connect-probe-kms PRIVATE cxx_std_17)
target_compile_options(connect-probe-kms PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(connect-probe-kms PRIVATE PkgConfig::LIBDRM)

add_executable(connect-probe-kms-xb30 probes/kms/connect-probe-kms-xb30.cpp)
target_compile_features(connect-probe-kms-xb30 PRIVATE cxx_std_17)
target_compile_options(connect-probe-kms-xb30 PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_link_libraries(connect-probe-kms-xb30 PRIVATE PkgConfig::LIBDRM PkgConfig::EGL)

if(GSTREAMER_FOUND AND GBM_FOUND)
  add_executable(connect-probe-vaapi-dmabuf
    probes/video/connect-probe-vaapi-dmabuf.cpp)
  target_compile_features(connect-probe-vaapi-dmabuf PRIVATE cxx_std_17)
  target_compile_options(connect-probe-vaapi-dmabuf PRIVATE
    -Wall -Wextra -Wpedantic -Werror)
  target_link_libraries(connect-probe-vaapi-dmabuf PRIVATE
    PkgConfig::GSTREAMER PkgConfig::EGL PkgConfig::GBM PkgConfig::LIBDRM)
endif()

add_executable(connect-probe-nvenc probes/nvenc/connect-probe-nvenc.cpp)
target_compile_features(connect-probe-nvenc PRIVATE cxx_std_17)
target_compile_options(connect-probe-nvenc PRIVATE -Wall -Wextra -Wpedantic -Werror)
target_include_directories(connect-probe-nvenc PRIVATE ${FFNVCODEC_INCLUDE_DIR})
target_link_libraries(connect-probe-nvenc PRIVATE ${CMAKE_DL_LIBS})

if(NVFBC_INCLUDE_DIR)
  add_executable(connect-probe-nvfbc probes/nvfbc/connect-probe-nvfbc.cpp)
  target_compile_features(connect-probe-nvfbc PRIVATE cxx_std_17)
  target_compile_options(connect-probe-nvfbc PRIVATE -Wall -Wextra -Wpedantic -Werror)
  target_include_directories(connect-probe-nvfbc PRIVATE
    ${NVFBC_INCLUDE_DIR}
    ${FFNVCODEC_INCLUDE_DIR})
  target_link_libraries(connect-probe-nvfbc PRIVATE ${CMAKE_DL_LIBS})

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

if(BUILD_TESTING)
  add_test(NAME kms-probe-self-test COMMAND connect-probe-kms --self-test)
  if(TARGET connect-probe-nvfbc)
    add_test(NAME nvfbc-probe-self-test COMMAND connect-probe-nvfbc --self-test)
    add_test(NAME video-pipeline-self-test
      COMMAND connect-probe-video-pipeline --self-test)
  endif()
endif()
