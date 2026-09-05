#!/usr/bin/env python3
"""Guard the no-video-frame reconnect presentation path (source checks)."""
import pathlib
import sys
import unittest

source = pathlib.Path(sys.argv.pop(1))
session = (source / "app/streaming/session.cpp").read_text()
toolbar = (source / "app/streaming/planktoolbar.cpp").read_text()
wayland = (source / "app/streaming/plankwaylandtoolbar.cpp").read_text()


def between(text, start, end):
    return text.split(start, 1)[1].split(end, 1)[0]


class ReconnectPresentation(unittest.TestCase):
    def test_status_is_published_before_decoder_suspension(self):
        begin = between(session, "bool Session::beginPlankReconnect", "bool Session::runPlankReconnect")
        self.assertLess(begin.index("setPlankReconnectStatus("), begin.index("suspendForReconnect()"))
        self.assertNotIn("updateOverlayText", begin)

    def test_native_surface_precedes_video_fallback(self):
        status = between(session, "void Session::setPlankReconnectStatus", "bool Session::beginPlankReconnect")
        self.assertIn("m_PlankToolbar->setReconnectStatus", status)
        self.assertIn("if (!nativeStatus && text[0] != '\\0')", status)
        native = between(toolbar, "bool PlankToolbar::setReconnectStatus", "void PlankToolbar::showReconnectPrompt")
        self.assertIn("redrawReconnectPrompt()", native)
        self.assertIn("m_WaylandReconnectPrompt->setVisible(true)", native)
        self.assertIn("wl_subsurface_set_desync(m_Subsurface)", wayland)
        self.assertIn("wl_surface_commit(m_Surface)", wayland)

    def test_timeout_and_logout_use_same_presentation(self):
        self.assertIn('setPlankReconnectStatus("Returning to the sign-in screen...", false)', session)
        self.assertIn('setPlankReconnectStatus("Workstation is taking longer to respond...", true)', session)

    def test_completion_clears_status_and_wait_restores_it(self):
        finish = between(session, "bool Session::finishPlankReconnect", "class PlankReconnectThread")
        self.assertIn('setPlankReconnectStatus("", false)', finish)
        hide = between(toolbar, "void PlankToolbar::hideReconnectPrompt", "void PlankToolbar::notifyWindowChanged")
        self.assertIn("m_ReconnectPromptVisible = false", hide)
        self.assertIn("setVisible(!m_ReconnectStatus.isEmpty())", hide)

    def test_status_has_no_action_buttons(self):
        paint = between(toolbar, "if (!m_ReconnectPromptVisible) {", "QFont titleFont;")
        self.assertIn("m_ReconnectStatus", paint)
        self.assertIn("m_WaylandReconnectPrompt->present(image)", paint)
        self.assertNotIn("drawButton", paint)
        button = between(toolbar, "void PlankToolbar::reconnectPromptPointerButton", "#else")
        self.assertIn("!m_ReconnectPromptVisible", button)


unittest.main()
