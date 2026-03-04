# Project-level configuration.
cmake_minimum_required(VERSION 3.14)
project(rockzero LANGUAGES CXX)

# The name of the executable created for the application. Change this to change
# the on-disk name of your application.
set(BINARY_NAME "rockzero")

# Explicitly opt in to modern CMake behaviors to avoid warnings with recent
# versions of CMake.
cmake_policy(VERSION 3.14...3.25)

# Keep compatibility with plugins that still use legacy add_custom_command
# signatures under newer CMake versions.
if(POLICY CMP0175)
  cmake_policy(SET CMP0175 OLD)
endif()

# Plugin CMake files can emit developer-only warnings; hide them from normal
# app builds.
set(CMAKE_SUPPRESS_DEVELOPER_WARNINGS 1 CACHE INTERNAL "")

# Define build configuration option.
get_property(IS_MULTICONFIG GLOBAL PROPERTY GENERATOR_IS_MULTI_CONFIG)
if(IS_MULTICONFIG)
  set(CMAKE_CONFIGURATION_TYPES "Debug;Profile;Release"
    CACHE STRING "" FORCE)
else()
  if(NOT CMAKE_BUILD_TYPE AND NOT CMAKE_CONFIGURATION_TYPES)
    set(CMAKE_BUILD_TYPE "Debug" CACHE
      STRING "Flutter build mode" FORCE)
    set_property(CACHE CMAKE_BUILD_TYPE PROPERTY STRINGS
      "Debug" "Profile" "Release")
  endif()
endif()
# Define settings for the Profile build mode.
set(CMAKE_EXE_LINKER_FLAGS_PROFILE "${CMAKE_EXE_LINKER_FLAGS_RELEASE}")
set(CMAKE_SHARED_LINKER_FLAGS_PROFILE "${CMAKE_SHARED_LINKER_FLAGS_RELEASE}")
set(CMAKE_C_FLAGS_PROFILE "${CMAKE_C_FLAGS_RELEASE}")
set(CMAKE_CXX_FLAGS_PROFILE "${CMAKE_CXX_FLAGS_RELEASE}")

# Use Unicode for all projects.
add_definitions(-DUNICODE -D_UNICODE)

# Compilation settings that should be applied to most targets.
#
# Be cautious about adding new options here, as plugins use this function by
# default. In most cases, you should add new options to specific targets instead
# of modifying this function.
function(APPLY_STANDARD_SETTINGS TARGET)
  target_compile_features(${TARGET} PUBLIC cxx_std_17)
  target_compile_options(${TARGET} PRIVATE /W4 /WX /wd"4100")
  target_compile_options(${TARGET} PRIVATE /EHsc)
  target_compile_definitions(${TARGET} PRIVATE "_HAS_EXCEPTIONS=0")
  target_compile_definitions(${TARGET} PRIVATE "$<$<CONFIG:Debug>:_DEBUG>")
endfunction()

# Flutter library and tool build rules.
set(FLUTTER_MANAGED_DIR "${CMAKE_CURRENT_SOURCE_DIR}/flutter")
add_subdirectory(${FLUTTER_MANAGED_DIR})

# Application build; see runner/CMakeLists.txt.
add_subdirectory("runner")

# Pre-fetch media_kit Windows dependency archives with retry & MD5 verification.
# This avoids transient network corruption causing plugin integrity check failure
# after `flutter clean`.
function(ENSURE_ARCHIVE_WITH_MD5 ARCHIVE_NAME ARCHIVE_URL ARCHIVE_MD5)
  set(ARCHIVE_PATH "${CMAKE_BINARY_DIR}/${ARCHIVE_NAME}")
  set(ARCHIVE_CACHE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/.download_cache")
  set(ARCHIVE_CACHE_PATH "${ARCHIVE_CACHE_DIR}/${ARCHIVE_NAME}")

  file(MAKE_DIRECTORY "${ARCHIVE_CACHE_DIR}")

  function(_validate_md5 FILE_PATH EXPECTED_MD5 OUT_VAR)
    if(NOT EXISTS "${FILE_PATH}")
      set(${OUT_VAR} FALSE PARENT_SCOPE)
      return()
    endif()

    file(MD5 "${FILE_PATH}" ACTUAL_MD5)
    if(ACTUAL_MD5 STREQUAL EXPECTED_MD5)
      set(${OUT_VAR} TRUE PARENT_SCOPE)
    else()
      set(${OUT_VAR} FALSE PARENT_SCOPE)
    endif()
  endfunction()

  _validate_md5("${ARCHIVE_PATH}" "${ARCHIVE_MD5}" BUILD_VALID)
  if(BUILD_VALID)
    message(STATUS "Archive verified: ${ARCHIVE_PATH}")
    return()
  endif()

  if(EXISTS "${ARCHIVE_PATH}")
    file(REMOVE "${ARCHIVE_PATH}")
    message(STATUS "Removed corrupt archive: ${ARCHIVE_PATH}")
  endif()

  _validate_md5("${ARCHIVE_CACHE_PATH}" "${ARCHIVE_MD5}" CACHE_VALID)
  if(CACHE_VALID)
    file(COPY_FILE "${ARCHIVE_CACHE_PATH}" "${ARCHIVE_PATH}" ONLY_IF_DIFFERENT)
    message(STATUS "Restored verified archive from cache: ${ARCHIVE_NAME}")
    return()
  endif()

  if(EXISTS "${ARCHIVE_CACHE_PATH}")
    file(REMOVE "${ARCHIVE_CACHE_PATH}")
    message(STATUS "Removed corrupt cache archive: ${ARCHIVE_CACHE_PATH}")
  endif()

  set(MAX_RETRIES 8)
  foreach(TRY_INDEX RANGE 1 ${MAX_RETRIES})
    message(STATUS "Downloading ${ARCHIVE_NAME} (attempt ${TRY_INDEX}/${MAX_RETRIES})")

    execute_process(
      COMMAND curl
        --fail
        --location
        --retry 2
        --retry-all-errors
        --retry-delay 2
        --connect-timeout 30
        --max-time 1800
        --output "${ARCHIVE_CACHE_PATH}"
        "${ARCHIVE_URL}"
      RESULT_VARIABLE CURL_STATUS_CODE
      OUTPUT_QUIET
      ERROR_VARIABLE CURL_STATUS_TEXT
    )

    set(STATUS_CODE ${CURL_STATUS_CODE})
    set(STATUS_TEXT "${CURL_STATUS_TEXT}")

    if(NOT STATUS_CODE EQUAL 0)
      file(
        DOWNLOAD
        "${ARCHIVE_URL}"
        "${ARCHIVE_CACHE_PATH}"
        STATUS DOWNLOAD_STATUS
        LOG DOWNLOAD_LOG
        SHOW_PROGRESS
        TIMEOUT 1800
        INACTIVITY_TIMEOUT 180
        TLS_VERIFY ON
      )

      list(GET DOWNLOAD_STATUS 0 STATUS_CODE)
      list(GET DOWNLOAD_STATUS 1 STATUS_TEXT)
    endif()

    if(STATUS_CODE EQUAL 0)
      _validate_md5("${ARCHIVE_CACHE_PATH}" "${ARCHIVE_MD5}" DOWNLOADED_VALID)
      if(DOWNLOADED_VALID)
        file(COPY_FILE "${ARCHIVE_CACHE_PATH}" "${ARCHIVE_PATH}" ONLY_IF_DIFFERENT)
        message(STATUS "Downloaded & verified: ${ARCHIVE_PATH}")
        return()
      endif()

      file(REMOVE "${ARCHIVE_CACHE_PATH}")
      message(WARNING "MD5 mismatch for ${ARCHIVE_NAME}, retrying...")
      continue()
    endif()

    file(REMOVE "${ARCHIVE_CACHE_PATH}")
    message(WARNING "Failed downloading ${ARCHIVE_NAME}: ${STATUS_TEXT}")
  endforeach()

  message(FATAL_ERROR "Failed to download verified archive after retries: ${ARCHIVE_NAME}")
endfunction()

ensure_archive_with_md5(
  "mpv-dev-x86_64-20230924-git-652a1dd.7z"
  "https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z"
  "a832ef24b3a6ff97cd2560b5b9d04cd8"
)

ensure_archive_with_md5(
  "ANGLE.7z"
  "https://github.com/alexmercerind/flutter-windows-ANGLE-OpenGL-ES/releases/download/v1.0.1/ANGLE.7z"
  "e866f13e8d552348058afaafe869b1ed"
)


# Generated plugin build rules, which manage building the plugins and adding
# them to the application.
include(flutter/generated_plugins.cmake)


# === Installation ===
# Support files are copied into place next to the executable, so that it can
# run in place. This is done instead of making a separate bundle (as on Linux)
# so that building and running from within Visual Studio will work.
set(BUILD_BUNDLE_DIR "$<TARGET_FILE_DIR:${BINARY_NAME}>")
set(CMAKE_VS_INCLUDE_INSTALL_TO_DEFAULT_BUILD 1)
if(CMAKE_INSTALL_PREFIX_INITIALIZED_TO_DEFAULT)
  set(CMAKE_INSTALL_PREFIX "${BUILD_BUNDLE_DIR}" CACHE PATH "..." FORCE)
endif()

if(CMAKE_INSTALL_PREFIX MATCHES "^[A-Za-z]:/Program Files")
  set(CMAKE_INSTALL_PREFIX "${PROJECT_BINARY_DIR}/runner/$<CONFIG>" CACHE PATH "..." FORCE)
endif()

set(INSTALL_BUNDLE_DATA_DIR "${CMAKE_INSTALL_PREFIX}/data")
set(INSTALL_BUNDLE_LIB_DIR "${CMAKE_INSTALL_PREFIX}")

install(TARGETS ${BINARY_NAME} RUNTIME DESTINATION "${CMAKE_INSTALL_PREFIX}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_ICU_DATA_FILE}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  COMPONENT Runtime)

install(FILES "${FLUTTER_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
  COMPONENT Runtime)

if(PLUGIN_BUNDLED_LIBRARIES)
  install(FILES "${PLUGIN_BUNDLED_LIBRARIES}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

set(NATIVE_ASSETS_DIR "${PROJECT_BUILD_DIR}native_assets/windows/")
if(EXISTS "${NATIVE_ASSETS_DIR}")
  install(DIRECTORY "${NATIVE_ASSETS_DIR}"
    DESTINATION "${INSTALL_BUNDLE_LIB_DIR}"
    COMPONENT Runtime)
endif()

set(FLUTTER_ASSET_DIR_NAME "flutter_assets")
install(CODE "
  file(REMOVE_RECURSE \"${INSTALL_BUNDLE_DATA_DIR}/${FLUTTER_ASSET_DIR_NAME}\")
  " COMPONENT Runtime)
install(DIRECTORY "${PROJECT_BUILD_DIR}/${FLUTTER_ASSET_DIR_NAME}"
  DESTINATION "${INSTALL_BUNDLE_DATA_DIR}" COMPONENT Runtime)

install(FILES "${AOT_LIBRARY}" DESTINATION "${INSTALL_BUNDLE_DATA_DIR}"
  CONFIGURATIONS Profile;Release
  COMPONENT Runtime)
