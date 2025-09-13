import argparse
import sys
import time
from contextlib import contextmanager

ANSI_BLU = "\033[94m"
ANSI_GRN = "\033[92m"
ANSI_YLW = "\033[93m"
ANSI_RED = "\033[91m"
ANSI_CYN = "\033[96m"
ANSI_RST = "\033[0m"
ANSI_GRY = "\033[90m"

# ANSI colors
ANSI_RST = "\033[0m"
ANSI_GRY = "\033[90m"
ANSI_CYN = "\033[36m"
ANSI_YLW = "\033[33m"
ANSI_RED = "\033[31m"


class _LogMethod:
    def __init__(self, level, color, tag):
        self.level = level
        self.color = color
        self.tag = tag

    def __get__(self, obj, objtype=None):
        def wrapper(*args, **kwargs):
            # Decide verbosity
            verbosity = getattr(obj, "verbosity", None)
            if verbosity is None:
                verbosity = objtype.verbosity

            # Decide threshold (only matters for debug)
            debug_threshold = getattr(obj, "debug_threshold", objtype.debug_threshold)

            # Prefix
            prefix = ""
            if obj and obj.prefix:
                prefix = f"({obj.prefix}) "
            elif not obj and objtype._global_prefix:
                prefix = f"({objtype._global_prefix}) "

            if self.level == 3:  # debug
                call_thr = kwargs.pop("threshold", 3)
                if verbosity >= call_thr and call_thr >= debug_threshold:
                    print(f"{self.color}{prefix}{self.tag}", *args, end=ANSI_RST+"\n")
            else:
                if verbosity >= self.level:
                    print(f"{self.color}{prefix}{self.tag}{ANSI_RST}", *args)
        return wrapper


class Logger:
    verbosity = 2
    debug_threshold = 3
    _global_prefix = ""

    def __init__(self, prefix="", verbosity=None, debug_threshold=None):
        self.prefix = prefix
        self.verbosity = verbosity
        self.debug_threshold = debug_threshold if debug_threshold is not None else Logger.debug_threshold

    @classmethod
    def set_prefix(cls, prefix):
        cls._global_prefix = prefix

    @classmethod
    def set_verbosity(cls, level):
        cls.verbosity = level

    @classmethod
    def set_debug_threshold(cls, thr):
        cls.debug_threshold = thr

    # Methods
    debug = _LogMethod(3, ANSI_GRY, "[>]")
    info  = _LogMethod(2, ANSI_CYN, "[+]")
    warn  = _LogMethod(1, ANSI_YLW, "[!]")
    error = _LogMethod(0, ANSI_RED, "[ERROR]")




class CmdArgumentParser(argparse.ArgumentParser):
    def exit(self, status=0, message=None):
        # Don't terminate the program
        if message:
            self._print_message(message, sys.stderr)

    def error(self, message):
        # Don't exit on parsing errors either
        self._print_message(f"error: {message}\n", sys.stderr)

    # Override parse_args to return True on help request
    def parse_args(self, args=None, namespace=None):
        if args is None:
            raise ValueError("args cannot be None")
        
        help_requested = '-h' in args or '--help' in args
        if help_requested:
            self.print_help()
            return None
        return super().parse_args(args, namespace)
    

def genmask(hi, lo):
    return ((1 << (hi - lo + 1)) - 1) << lo

def getbits(value, hi, lo):
    mask = (1 << (hi - lo + 1)) - 1
    return (value >> lo) & mask

def setbits(orig, hi, lo, value):
    mask = (1 << (hi - lo + 1)) - 1
    orig &= ~(mask << lo)
    orig |= (value & mask) << lo
    return orig



class TimeoutError(Exception):
    pass

@contextmanager
def timeout(seconds, message="Timeout expired"):
    """Context manager for enforcing timeouts."""
    start = time.monotonic()
    yield
    elapsed = time.monotonic() - start
    if elapsed > seconds:
        Logger.error(f"{message} (>{seconds}s, elapsed {elapsed:.2f}s)")
        


def parse_hostportstr(s, default_host='localhost', default_port=3333):
    try:
        if ":" in s:
            host, port = s.split(":")
            host = host if host else default_host
            port = int(port) if port else default_port
        else:
            host, port = default_host, int(s)
    except ValueError:
        Logger.error("Invalid TCP argument. Use format host:port or port.")
        return
    return host, port