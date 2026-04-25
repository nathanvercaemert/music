#!/usr/bin/env python3
import ctypes
import ctypes.util
import os
import sys
import time


DISPLAY = os.environ.get("DISPLAY", ":0")
WINDOW_ORDER = [
    "main",
    "909",
    "808",
    "kick-mix",
    "voice-spectral-governance",
    "send-voice-spectral-governance",
    "voice-saturation",
    "send-voice-saturation",
    "saturation-spectral-governance",
    "send-saturation-spectral-governance",
    "output",
]
MARGIN_X = 40
MARGIN_Y = 40
GAP_X = 24
GAP_Y = 24


class XWindowAttributes(ctypes.Structure):
    _fields_ = [
        ("x", ctypes.c_int),
        ("y", ctypes.c_int),
        ("width", ctypes.c_int),
        ("height", ctypes.c_int),
        ("border_width", ctypes.c_int),
        ("depth", ctypes.c_int),
        ("visual", ctypes.c_void_p),
        ("root", ctypes.c_ulong),
        ("class_", ctypes.c_int),
        ("bit_gravity", ctypes.c_int),
        ("win_gravity", ctypes.c_int),
        ("backing_store", ctypes.c_int),
        ("backing_planes", ctypes.c_ulong),
        ("backing_pixel", ctypes.c_ulong),
        ("save_under", ctypes.c_int),
        ("colormap", ctypes.c_ulong),
        ("map_installed", ctypes.c_int),
        ("map_state", ctypes.c_int),
        ("all_event_masks", ctypes.c_long),
        ("your_event_mask", ctypes.c_long),
        ("do_not_propagate_mask", ctypes.c_long),
        ("override_redirect", ctypes.c_int),
        ("screen", ctypes.c_void_p),
    ]


def load_x11():
    lib = ctypes.cdll.LoadLibrary(ctypes.util.find_library("X11"))
    lib.XOpenDisplay.restype = ctypes.c_void_p
    lib.XDefaultRootWindow.argtypes = [ctypes.c_void_p]
    lib.XDefaultRootWindow.restype = ctypes.c_ulong
    lib.XQueryTree.argtypes = [
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.POINTER(ctypes.c_ulong),
        ctypes.POINTER(ctypes.c_ulong),
        ctypes.POINTER(ctypes.POINTER(ctypes.c_ulong)),
        ctypes.POINTER(ctypes.c_uint),
    ]
    lib.XQueryTree.restype = ctypes.c_int
    lib.XFetchName.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(ctypes.c_char_p)]
    lib.XFetchName.restype = ctypes.c_int
    lib.XMoveResizeWindow.argtypes = [
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.c_int,
        ctypes.c_int,
        ctypes.c_uint,
        ctypes.c_uint,
    ]
    lib.XMoveWindow.argtypes = [
        ctypes.c_void_p,
        ctypes.c_ulong,
        ctypes.c_int,
        ctypes.c_int,
    ]
    lib.XMapRaised.argtypes = [ctypes.c_void_p, ctypes.c_ulong]
    lib.XFlush.argtypes = [ctypes.c_void_p]
    lib.XFree.argtypes = [ctypes.c_void_p]
    lib.XCloseDisplay.argtypes = [ctypes.c_void_p]
    lib.XGetWindowAttributes.argtypes = [ctypes.c_void_p, ctypes.c_ulong, ctypes.POINTER(XWindowAttributes)]
    lib.XGetWindowAttributes.restype = ctypes.c_int
    lib.XDisplayWidth.argtypes = [ctypes.c_void_p, ctypes.c_int]
    lib.XDisplayWidth.restype = ctypes.c_int
    return lib


def list_windows(lib, display):
    root = lib.XDefaultRootWindow(display)
    pending = [root]
    seen = set()
    results = []

    while pending:
        win = pending.pop()
        if win in seen:
            continue
        seen.add(win)

        root_ret = ctypes.c_ulong()
        parent_ret = ctypes.c_ulong()
        children = ctypes.POINTER(ctypes.c_ulong)()
        count = ctypes.c_uint()
        if not lib.XQueryTree(display, win, ctypes.byref(root_ret), ctypes.byref(parent_ret), ctypes.byref(children), ctypes.byref(count)):
            continue

        try:
            for i in range(count.value):
                child = children[i]
                pending.append(child)

                name_ptr = ctypes.c_char_p()
                name = None
                if lib.XFetchName(display, child, ctypes.byref(name_ptr)) and name_ptr.value:
                    name = name_ptr.value.decode("utf-8", "replace")
                    lib.XFree(name_ptr)
                if name:
                    attrs = XWindowAttributes()
                    lib.XGetWindowAttributes(display, child, ctypes.byref(attrs))
                    results.append((child, name, attrs))
        finally:
            if children:
                lib.XFree(children)

    return results


def pick_named_windows(windows):
    picked = {}

    for win, name, attrs in windows:
        area = attrs.width * attrs.height
        current = picked.get(name)
        if current is None or area > current[2].width * current[2].height:
            picked[name] = (win, name, attrs)

    return picked


def main():
    os.environ["DISPLAY"] = DISPLAY
    lib = load_x11()
    display = lib.XOpenDisplay(None)
    if not display:
      return 1

    try:
        deadline = time.time() + 10.0
        pending = set(WINDOW_ORDER)
        screen_width = lib.XDisplayWidth(display, 0)
        next_x = MARGIN_X
        next_y = MARGIN_Y
        row_height = 0

        while pending and time.time() < deadline:
            named_windows = pick_named_windows(list_windows(lib, display))
            for name in WINDOW_ORDER:
                if name not in pending:
                    continue
                if name not in named_windows:
                    continue

                win, _name, attrs = named_windows[name]
                pending.remove(name)

                if next_x > MARGIN_X and next_x + attrs.width > screen_width - MARGIN_X:
                    next_x = MARGIN_X
                    next_y += row_height + GAP_Y
                    row_height = 0

                lib.XMoveWindow(display, win, next_x, next_y)
                lib.XMapRaised(display, win)
                next_x += attrs.width + GAP_X
                row_height = max(row_height, attrs.height)
            lib.XFlush(display)
            if pending:
                time.sleep(0.2)

        return 0 if not pending else 1
    finally:
        lib.XCloseDisplay(display)


if __name__ == "__main__":
    sys.exit(main())
