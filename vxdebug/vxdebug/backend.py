from vxdebug.utils import *
from vxdebug.transport import TCPTransport
from time import time, sleep
from dataclasses import dataclass
import enum

TIMEOUT    = 10     # Timeout for operations in seconds
TIMESTEP   = 0.1    # Time step for polling operations

PLATFORM_ID_MAP = {
    1: "Vortex"
}

################################################################################
# Vortex Debugger Backend
# ========================
# This module provides the Backend class that abstracts low level access to 
# DM registers

@dataclass(frozen=True)
class RegInfo:
    addr: int
    fields: dict[str, tuple[int, int]]  # field name -> (bit_offset, bit_width)

class DMReg(enum.Enum):
    WSEL = RegInfo(0x00, {
        "winsel": (7,0),
        "warpsel": (31,16)
    })
    WSTATUS = RegInfo(0x01, {
        "wstatus": (31,0)
    })
    WMASK = RegInfo(0x02, {
        "wmask": (31,0)
    })
    WCTRL = RegInfo(0x03, {
        "haltreq":      (0, 0),
        "resumereq":    (1, 1),
        "stepreq":      (2, 2),
        "stepstate":    (4, 3),
        "ndmreset":     (30, 30),
        "dmactive":     (31, 31)
    })
    PLATFORM = RegInfo(0x04, {
        "platform":     (31, 29),
        "num_clusters": (28, 24),
        "num_cores":    (23, 16),
        "num_warps":    (15, 8),
        "num_threads":  (7, 0)
    })
    DSCRATCH = RegInfo(0x05, {
        "data": (31,0)
    })
    DPC = RegInfo(0x06, {
        "pc": (31,0)
    })


class Backend:
    def __init__(self):
        self.transport = None
        self.log = Logger("Backend", debug_threshold=3)

        self.plat_info = None
        self.selected_wid = None
        self.selected_warp_pc = None

    def transport_setup(self, name):
        if name.lower() == "tcp":
            self.transport = TCPTransport()
        else:
            raise ValueError(f"Unknown transport '{name}'")
    
    def transport_is_connected(self):
        return self.transport.is_connected() if self.transport else False

    def transport_connect(self, **kwargs):
        return self.transport.connect(**kwargs)

    def transport_disconnect(self):
        if self.transport and self.transport.is_connected():
            self.transport.disconnect()

    def initialize(self):
        if not self.transport or not self.transport.is_connected():
            return
        
        self.log.debug("Initializing backend...")

        # Try to wake up DM
        rc = self._wakedm()
        if not rc:
            self.log.error("Failed to wake up DM.")
            return

        # Get platform info
        self.plat_info = self._get_platform_info()
        if not self.plat_info:
            self.log.error("Failed to get platform info.")
            return

        self.log.debug("Backend initialized.")
        self._print_platform_info()


    ############################################################################
    # Helpers
    def _print_platform_info(self):
        if not self.plat_info:
            Logger.warn("No platform information available.")
            return
        pltinfo  = f"\tPlatformID:  0x{self.plat_info['platform_id']:x}\n"
        pltinfo += f"\tPlatform:    {self.plat_info['platform']}\n"
        pltinfo += f"\tClusters:    {self.plat_info['num_clusters']}\n"
        pltinfo += f"\tCores:       {self.plat_info['num_cores']}\n"
        pltinfo += f"\tWarps:       {self.plat_info['num_warps']}\n"
        pltinfo += f"\tThreads:     {self.plat_info['num_threads']}\n"
        pltinfo += f"\tTotal Warps: {self.plat_info['num_total_warps']}\n"
        Logger.info(f"Platform Info:\n{pltinfo}")

    def _get_dmreg_by_name(self, name: str):
        try:
            reg = DMReg[name.upper()]
            return reg
        except KeyError:
            raise ValueError(f"Unknown register '{name}'")

    ############################################################################
    # Low Level Register Access
    def reg_read(self, reg: DMReg, field: str = None):
        if not self.transport or not self.transport.is_connected():
            self.log.error("Transport not connected.")
            return None
        
        if reg not in DMReg:
            raise ValueError(f"Unknown register '{reg}'")

        addr = reg.value.addr
        raw = self.transport.reg_read(addr)
        if raw is None:
            self.log.error(f"Failed to read register {reg.name} (0x{addr:02X})")
            return None

        if field:
            if field not in reg.value.fields:
                raise ValueError(f"Unknown field '{field}' in register {reg.name}")

            hi, lo = reg.value.fields[field]
            value = getbits(raw, hi, lo)
            self.log.debug(f"DMReg Rd: {reg.name}.{field} = 0x{value:X}")
            return value
        else:
            self.log.debug(f"DMReg Rd: {reg.name} = 0x{raw:X}")
            return raw

    def reg_write(self, reg: DMReg, value: int, field: str = None):
        if not self.transport or not self.transport.is_connected():
            self.log.error("Transport not connected.")
            return False
        if reg not in DMReg:
            raise ValueError(f"Unknown register '{reg}'")    
   
        addr = reg.value.addr
        if field:
            if field not in reg.value.fields:
                raise ValueError(f"Unknown field '{field}' in register {reg.name}")           
            
            # Read current value
            current = self.transport.reg_read(addr)
            if current is None:
                self.log.error(f"Failed to read register {reg.name} (0x{addr:02X}) for field update")
                return False
            hi, lo = reg.value.fields[field]
            # Update field
            new_value = setbits(current, hi, lo, value)
            self.log.debug(f"DMReg Wr: {reg.name}.{field} = 0x{value:X} (Reg: 0x{new_value:X})")

            # Write back
            return self.transport.reg_write(addr, new_value)
        else:
            self.log.debug(f"DMReg Wr: {reg.name} = 0x{value:X}")
            return self.transport.reg_write(addr, value)


    ########################################
    # API
    ########################################
    def _wakedm(self):
        self.log.debug("Waking up DM...")
        # Wait till ndmreset is cleared
        with timeout(TIMEOUT, "Timeout waiting for ndmreset to clear"):
            while True:
                ndmreset = self.reg_read(DMReg.WCTRL, "ndmreset")
                if ndmreset is None:
                    return False
                if ndmreset == 0:
                    break
                sleep(TIMESTEP)

        # Write to dmactive and try to wake up DM
        with timeout(TIMEOUT, "Timeout waiting for DM to wake up"):
            while True:
                dmactive = self.reg_read(DMReg.WCTRL, "dmactive")
                if dmactive is None:
                    return False
                if dmactive == 1:
                    break
                self.reg_write(DMReg.WCTRL, 1, "dmactive")
                sleep(TIMESTEP)

        self.log.debug("DM is awake.")
        return True


    def _get_platform_info(self):
        plat = self.reg_read(DMReg.PLATFORM)
        if plat is None:
            return None
        platinfo = {
            "platform_id":  getbits(plat, 31, 29),
            "num_clusters": getbits(plat, 28, 24),
            "num_cores":    getbits(plat, 23, 16),
            "num_warps":    getbits(plat, 15, 8),
            "num_threads":  getbits(plat, 7, 0)
        }
        platinfo["platform"] = PLATFORM_ID_MAP.get(platinfo["platform_id"], "Unknown")
        platinfo["num_total_warps"] = platinfo["num_clusters"] * platinfo["num_cores"] * platinfo["num_warps"]
        return platinfo
    

    def _reset_platform(self):
        self.log.info("Resetting target platform...")
        self.reg_write(DMReg.WCTRL, 1, "ndmreset")
        # Wait for ndmreset to clear
        with timeout(TIMEOUT, "Timeout waiting for ndmreset to clear"):
            while True:
                ndmreset = self.reg_read(DMReg.WCTRL, "ndmreset")
                if ndmreset is None:
                    return False
                if ndmreset == 0:
                    break
                sleep(TIMESTEP)
        self.log.info("Target platform reset complete.")
        return True

    def _get_warp_status(self):
        n_win = (self.plat_info['num_total_warps'] + 31) // 32
        status = {}
        for win in range(n_win):
            self.reg_write(DMReg.WSEL, win, "winsel")
            wstatus = self.reg_read(DMReg.WSTATUS, "wstatus")
            if wstatus is None:
                return None
            for i in range(32):
                warp_id = win * 32 + i
                if warp_id >= self.plat_info['num_total_warps']:
                    break

                warp_status = (wstatus >> i) & 1
                warp_pc = None
                if warp_status == 1:  # Halted
                    # Read PC from DPC
                    self._select_a_warp(warp_id)
                    warp_pc = self.reg_read(DMReg.DPC)
                    if warp_pc is None:
                        return None
                status[warp_id] = (warp_status, warp_pc)
        return status

    def _select_warps(self, warp_ids=None):
        if not warp_ids:
            warp_ids = list(range(self.plat_info['num_total_warps']))
        
        # Create a mask for warps to select
        warp_mask = 0
        for wid in warp_ids:
            warp_mask |= (1 << wid)
        
        # Iterate over all windows and set mask
        for win in range((self.plat_info['num_total_warps'] + 31) // 32):
            mask = (warp_mask >> (win * 32)) & 0xFFFFFFFF
            if mask:
                self.reg_write(DMReg.WSEL, win, "winsel")
                self.reg_write(DMReg.WMASK, mask, "wmask")
    
    def _select_a_warp(self, warp_id):
        # Select a single warp for halt/resume/step
        self.reg_write(DMReg.WSEL, warp_id, "warpsel")
        self.selected_wid = warp_id
    
    def _get_selected_warp(self):
        return self.selected_wid

    def _halt_warps(self, warp_ids=None):
        self._select_warps(warp_ids)
        self.reg_write(DMReg.WCTRL, 1, "haltreq")

        
    def _resume_warps(self, warp_ids=None):
        self._select_warps(warp_ids)
        self.reg_write(DMReg.WCTRL, 1, "resumereq")


    def _all_halted(self):
        wstatus = self._get_warp_status()
        if wstatus is None:
            return False
        return all(status[0] == 1 for status in wstatus.values())

    def _all_running(self):
        wstatus = self._get_warp_status()
        if wstatus is None:
            return False
        return all(status[0] == 0 for status in wstatus.values())

    def _any_halted(self):
        wstatus = self._get_warp_status()
        if wstatus is None:
            return False
        return any(status[0] == 1 for status in wstatus.values())

    def _any_running(self):
        wstatus = self._get_warp_status()
        if wstatus is None:
            return False
        return any(status[0] == 0 for status in wstatus.values())

    def _step_warp(self, warp_id=None):
        if warp_id is not None:
            self._select_a_warp(warp_id)
        self.reg_write(DMReg.WCTRL, 1, "stepreq")

        # Wait for stepstate to go to 0 (idle)
        with timeout(TIMEOUT, "Timeout waiting for step to complete"):
            while True:
                stepstate = self.reg_read(DMReg.WCTRL, "stepstate")
                if stepstate is None:
                    return False
                if stepstate == 0:
                    break
                sleep(TIMESTEP)
        self.selected_warp_pc = self.reg_read(DMReg.DPC)
        self.log.debug(f"Warp {self.selected_wid} stepped to PC=0x{self.selected_warp_pc:X}")
        return True


    ############################################################################
