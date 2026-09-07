QT += core gui
CONFIG += console c++17
CONFIG -= app_bundle
TEMPLATE = app
TARGET = macos-preview-launch
isEmpty(PLANK_CLIENT_SOURCE): error(Set PLANK_CLIENT_SOURCE to the exact clean Client worktree)
isEmpty(PLANK_COMMON_SOURCE): error(Set PLANK_COMMON_SOURCE to its exact common-c worktree)
SOURCES += $$PWD/macos-preview-launch.cpp \
    $$PLANK_CLIENT_SOURCE/app/backend/outputtopology.cpp
INCLUDEPATH += $$PLANK_CLIENT_SOURCE/app $$PLANK_COMMON_SOURCE/src
QMAKE_CXXFLAGS += -Wall -Wextra -Werror
