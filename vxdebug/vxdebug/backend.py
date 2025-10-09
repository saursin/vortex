from vxdebug.utils import *
from vxdebug.transport import TCPTransport
from time import time, sleep
from dataclasses import dataclass
import subprocess, tempfile, struct, os
import enum
import shutil

TIMEOUT    = 60     # Timeout for operations in seconds
TIMESTEP   = 0.1    # Time step for polling operations

RISCV_TOOLCHAIN_PREFIX = "riscv64-unknown-elf"

PLATFORM_ID_MAP = {
    1: "Vortex"
}

################################################################################
# RISC-V Definitions
################################################################################
RVREGS = {
    "zero":0,  "ra": 1,   "sp": 2,   "gp" : 3,
    "tp"  :4,  "t0": 5,   "t1": 6,   "t2" : 7,
    "s0"  :8,  "fp": 8,   "s1": 9,   "a0" : 10,
    "a1"  :11, "a2": 12,  "a3": 13,  "a4" : 14,
    "a5"  :15, "a6": 16,  "a7": 17,  "s2" : 18,
    "s3"  :19, "s4": 20,  "s5": 21,  "s6" : 22,
    "s7"  :23, "s8": 24,  "s9": 25,  "s10": 26,
    "s11" :27, "t3": 28,  "t4": 29,  "t5" : 30,
    "t6"  :31
}

RVCSRS = {
    "vendorid": 0xf11,
    "archid"  : 0xf12,
    "impid"   : 0xf13,
    "hartid"  : 0xf14,

    "mcycle"   : [0xb00, 0xb80],
    "instret"  : [0xb02, 0xb82],

    "vx_thread_id":         0xCC0,
    "vx_warp_id":           0xCC1,
    "vx_core_id":           0xCC2,
    "vx_active_warps":      0xCC3,
    "vx_active_threads":    0xCC4,
    "vx_num_threads":       0xFC0,
    "vx_num_warps":         0xFC1,
    "vx_num_cores":         0xFC2,
    "vx_local_mem_base":    0xFC3,
    "vx_dscratch":          0x7B2
}


# Debug Module Definitions
@dataclass(frozen=True)
class RegInfo:
    addr: int
    fields: dict[str, tuple[int, int]]  # field name -> (hi, lo)

class DMReg(enum.Enum):
    PLATFORM = RegInfo(0x00, {
        "platformid":  (31, 28),
        "numclusters": (27, 21),
        "numcores":    (20, 12),
        "numwarps":    (11, 3),
        "numthreads":  (2, 0)
    })
    DSELECT = RegInfo(0x01, {
        "winsel": (31,22),
        "warpsel": (21,7),
        "threadsel": (6,0)
    })
    WMASK = RegInfo(0x02, {
        "mask": (31,0)
    })
    WSTATUS = RegInfo(0x03, {
        "status": (31,0)
    })
    DCTRL = RegInfo(0x04, {
        "dmactive":     (31, 31),
        "ndmreset":     (30, 30),
        "allhalted":    (29, 29),
        "anyhalted":    (28, 28),
        "allrunning":   (27, 27),
        "anyrunning":   (26, 26),
        "injectstate":  (8, 7),
        "injectreq":    (6, 6),
        "stepstate":    (5, 4),
        "stepreq":      (3, 3),
        "resethaltreq": (2, 2),
        "resumereq":    (1, 1),
        "haltreq":      (0, 0)
    })
    DPC = RegInfo(0x05, {
        "pc": (31,0)
    })
    INJECT = RegInfo(0x06, {
        "instr": (31, 0)
    })
    DSCRATCH = RegInfo(0x07, {
        "data": (31,0)
    })

################################################################################
# Utility function to assemble RISC-V instructions
def rvassemble(instr):
    """
    Assemble a single RISC-V instruction into binary and return it as an int.
    Requires riscv64-unknown-elf-gcc and objcopy in PATH.
    """
    instrs = []
    if isinstance(instr, str):
        instrs = [instr]
    elif isinstance(instr, list):
        instrs = instr
    else:
        raise ValueError("Instruction must be a string or list of strings")

    with tempfile.TemporaryDirectory() as tmpdir:
        asm_path = os.path.join(tmpdir, "vxdbg_instrs.S")
        obj_path = os.path.join(tmpdir, "vxdbg_instrs.o")
        bin_path = os.path.join(tmpdir, "vxdbg_instrs.bin")
        
        # Create a minimal assembly file
        with open(asm_path, "w") as f:
            f.write(".option push\n"
                    ".option norvc\n"        # <— force 32-bit encodings
                    ".text\n.balign 4\n"
                    ".globl _start\n_start:\n"
                    + ";\n".join(instrs) + "\n"
                    ".option pop\n")
            
        # print(f"Assembly file:\n{open(asm_path).read()}")

        # Assemble to bin file & extract binary
        subprocess.run([f"{RISCV_TOOLCHAIN_PREFIX}-as", asm_path, "-o", obj_path], check=True)
        subprocess.run([f"{RISCV_TOOLCHAIN_PREFIX}-objcopy", "-O", "binary", obj_path, bin_path], check=True)

        # Read the binary instructions (4 bytes at a time)
        instrs = []
        with open(bin_path, "rb") as f:
            while True:
                bytes = f.read(4)
                if not bytes:
                    break
                if len(bytes) < 4:
                    raise ValueError("Instruction binary size is not a multiple of 4 bytes")
                instrs.append(struct.unpack("<I", bytes)[0])  # Little-endian

        # Return the assembled instructions
        if len(instrs) == 1:
            return instrs[0]
        return instrs


################################################################################
# Backend Class
################################################################################
class Backend:
    def __init__(self):
        self.transport = None
        self.log = Logger("Backend", debug_threshold=3)

        self.plat_info = None

        self.selected_wid = None
        self.selected_tid = None
        self.selected_warp_pc = None

        self.breakpoints = {}

        # Check if riscv64-unknown-elf-gcc is available
        if not shutil.which(f"{RISCV_TOOLCHAIN_PREFIX}-gcc"):
            self.log.warn(f"{RISCV_TOOLCHAIN_PREFIX}-gcc not found in PATH. Instruction injection and any dependent functionality will not work.")

    def transport_setup(self, name: str):
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
        rc = self.wakedm()
        if not rc:
            self.log.error("Failed to wake up DM.")
            return

        # Get platform info
        self.plat_info = self.get_platform_info()
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

    def __assert_warpthread_selected(self):
        if self.selected_wid is None:
            self.log.error("No warp selected.")
            return False
        if self.selected_tid is None:
            self.log.error("No thread selected.")
            return False
        return True

    def _get_dmreg_by_name(self, name: str):
        try:
            reg = DMReg[name.upper()]
            return reg
        except KeyError:
            raise ValueError(f"Unknown register '{name}'")
        
    def _get_regnames(self):
        return ["pc"] + list(RVREGS.keys()) +  list(RVCSRS.keys())
        
    ############################################################################
    # Low Level DM Register Access

    def _dmreg_read(self, reg: DMReg, field: str = None):
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
            self.log.debug(f"DMReg (0x{addr:02X}) Rd: {reg.name}.{field} = 0x{value:X}")
            return value
        else:
            self.log.debug(f"DMReg (0x{addr:02X}) Rd: {reg.name} = 0x{raw:X}")
            return raw


    def _dmreg_write(self, reg: DMReg, value: int, field: str = None):
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
                self.log.error(f"Failed to read register {reg.name} (RegAddr: 0x{addr:02X}) for field update")
                return False
            
            # Update field
            hi, lo = reg.value.fields[field]
            new_value = setbits(current, hi, lo, value)
            self.log.debug(f"DMReg (0x{addr:02X}) Wr: {reg.name}.{field} = 0x{value:X} (new reg value: 0x{new_value:08X})")

            # Write back
            return self.transport.reg_write(addr, new_value)
        else:
            self.log.debug(f"DMReg (0x{addr:02X}) Wr: {reg.name} = 0x{value:X}")
            return self.transport.reg_write(addr, value)

    
    def _print_dmreg(self, reg: DMReg):
        if reg not in DMReg:
            raise ValueError(f"Unknown register '{reg}'")
        
        raw = self._dmreg_read(reg)
        if raw is None:
            return
        
        reginfo = f"{reg.name} (0x{reg.value.addr:02X}): 0x{raw:08X}\n"
        for field, (hi, lo) in reg.value.fields.items():
            value = getbits(raw, hi, lo)
            reginfo += f"\t{field} [{hi}:{lo}] = 0x{value:X}\n"
        Logger.info(f"DM Reg: {reginfo}")


    ########################################
    # API
    ########################################
    def wakedm(self):
        """
        Wake up the Debug Module if it is disabled.
        """
        # Wait till ndmreset is cleared
        self.log.debug("Waiting for ndmreset to clear (if set)...")
        with timeout(TIMEOUT, "Timeout waiting for ndmreset to clear"):
            while True:
                ndmreset = self._dmreg_read(DMReg.DCTRL, "ndmreset")
                if ndmreset is None:
                    return False
                if ndmreset == 0:
                    break
                sleep(TIMESTEP)

       # Write to dmactive and try to wake up DM
        self.log.debug("Waking up DM...")
        with timeout(TIMEOUT, "Timeout waiting for DM to wake up"):
            while True:
                dmactive = self._dmreg_read(DMReg.DCTRL, "dmactive")
                if dmactive is None:
                    self.log.error("Failed to read DM active status.")
                    return False
                if dmactive == 1:
                    break
                self._dmreg_write(DMReg.DCTRL, 1, "dmactive")
                sleep(TIMESTEP)

        self.log.debug("DM is awake.")
        return True


    def reset_platform(self, halt_warps=False, halt_warp_ids=None):
        """
        Reset the target platform. 
        If halt_warps is True, all warps will be halted after reset.
        """
        if halt_warps:
            self.select_warps(halt_warp_ids)
            self._dmreg_write(DMReg.DCTRL, 1, "resethaltreq")

        self.log.info("Resetting target platform...")
        self._dmreg_write(DMReg.DCTRL, 1, "ndmreset")

        # Wait for ndmreset to clear
        with timeout(TIMEOUT, "Timeout waiting for ndmreset to clear"):
            while True:
                ndmreset = self._dmreg_read(DMReg.DCTRL, "ndmreset")
                if ndmreset is None:
                    return False
                if ndmreset == 0:
                    break
                sleep(TIMESTEP)
        self.log.info("Target platform reset complete.")

        if halt_warps:
            # Wait for all warps to halt
            with timeout(TIMEOUT, "Timeout waiting for warps to halt after reset"):
                while True:
                    if halt_warp_ids is None and self.all_halted():
                        self.log.info("All warps halted after reset.")
                        break
                    elif halt_warp_ids is not None and self.any_halted():
                        self.log.info("Some warps halted after reset.")
                        break
                    sleep(TIMESTEP)

        return True


    def get_platform_info(self):
        """
        Get platform information from the DM.
        """
        plat = self._dmreg_read(DMReg.PLATFORM)
        if plat is None:
            return None
        platinfo = {
            "platform_id":  getbits(plat, *DMReg.PLATFORM.value.fields["platformid"],),
            "num_clusters": getbits(plat, *DMReg.PLATFORM.value.fields["numclusters"]),
            "num_cores":    getbits(plat, *DMReg.PLATFORM.value.fields["numcores"]),
            "num_warps":    getbits(plat, *DMReg.PLATFORM.value.fields["numwarps"]),
            "num_threads":  2**getbits(plat, *DMReg.PLATFORM.value.fields["numthreads"])
        }
        platinfo["platform"] = PLATFORM_ID_MAP.get(platinfo["platform_id"], "Unknown")
        platinfo["num_total_cores"] = platinfo["num_clusters"] * platinfo["num_cores"]
        platinfo["num_total_warps"] = platinfo["num_total_cores"] * platinfo["num_warps"]

        # Get ISA information
        # misa = self._read_reg("misa") # TODO
        return platinfo
    

    def get_warp_status(self, get_pc=False):
        """
        Get the status of all warps. 
        If get_pc is True, also read the PC of halted warps.
        """
        sel_wid, sel_tid = self.selected_wid, self.selected_tid

        n_win = (self.plat_info['num_total_warps'] + 31) // 32
        status = {}
        for win in range(n_win):
            self._dmreg_write(DMReg.DSELECT, win, "winsel")
            wstatus = self._dmreg_read(DMReg.WSTATUS, "status")
            if wstatus is None:
                return None
            for i in range(32):
                warp_id = win * 32 + i
                if warp_id >= self.plat_info['num_total_warps']:
                    break

                warp_status = (wstatus >> i) & 1
                status[warp_id] = {'halted': warp_status}
                    
                
                if get_pc:
                    if warp_status == 1:  # Halted, read PC
                        self.select_a_warp(warp_id)
                        warp_pc = self._dmreg_read(DMReg.DPC)
                        status[warp_id]['pc'] = warp_pc
                    else:
                        status[warp_id]['pc'] = None

        # May have modified selected status warp/thread, restore
        if get_pc:
            if sel_wid is None:
                self.selected_wid = None
            else:
                self.select_a_warp(sel_wid)
            if sel_tid is None:
                self.selected_tid = None
            else:
                self.select_a_thread(sel_tid)
        return status


    def select_warps(self, warp_ids=None):
        """
        Select warps by their IDs. 
        If warp_ids is None or empty, select all warps.
        """
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
                self._dmreg_write(DMReg.DSELECT, win, "winsel")
                self._dmreg_write(DMReg.WMASK, mask, "mask")
    
    
    def select_a_warp(self, warp_id):
        """
        Select a single warp by its ID for debugging
        """
        if warp_id < 0 or warp_id >= self.plat_info['num_total_warps']:
            self.log.error(f"Invalid warp ID {warp_id}")
            return False
        self._dmreg_write(DMReg.DSELECT, warp_id, "warpsel")
        self.selected_wid = warp_id


    def select_a_thread(self, thread_id):
        """
        Select a single thread by its ID for debugging
        """
        if thread_id < 0 or thread_id >= self.plat_info['num_threads']:
            self.log.error(f"Invalid thread ID {thread_id}")
            return False
        self.selected_tid = thread_id
        self._dmreg_write(DMReg.DSELECT, thread_id, "threadsel")
        return True
    

    def get_selected_warp(self):
        """
        Get the currently selected warp ID.
        """
        return self.selected_wid

    def get_selected_thread(self):
        """
        Get the currently selected thread ID.
        """
        return self.selected_tid

    def halt_warps(self, warp_ids=None):
        """
        Halt warps by their IDs.
        If warp_ids is None or empty, halt all warps.
        """
        self.log.info(f"Halting warps... [{', '.join(map(str, warp_ids)) if warp_ids else 'all'}]")
        self.select_warps(warp_ids)
        self._dmreg_write(DMReg.DCTRL, 1, "haltreq")

    def resume_warps(self, warp_ids=None):
        """
        Resume warps by their IDs.
        If warp_ids is None or empty, resume all warps.
        """
        self.select_warps(warp_ids)
        self._dmreg_write(DMReg.DCTRL, 1, "resumereq")

    def all_halted(self):
        """
        Check if all warps are halted.
        """
        allhalted = self._dmreg_read(DMReg.DCTRL, "allhalted")
        if allhalted is None:
            return False
        return allhalted == 1

    def all_running(self):
        """
        Check if all warps are running.
        """
        allrunning = self._dmreg_read(DMReg.DCTRL, "allrunning")
        if allrunning is None:
            return False
        return allrunning == 1

    def any_halted(self):
        """
        Check if any warp is halted.
        """
        anyhalted = self._dmreg_read(DMReg.DCTRL, "anyhalted")
        if anyhalted is None:
            return False
        return anyhalted == 1

    def any_running(self):
        """
        Check if any warp is running.
        """
        anyrunning = self._dmreg_read(DMReg.DCTRL, "anyrunning")
        if anyrunning is None:
            return False
        return anyrunning == 1
        
    def step_warp(self, warp_id=None):
        """
        Step the selected warp by one instruction.
        """
        if warp_id is not None:
            self.select_a_warp(warp_id)

        # if all warps halted, may cause deadlock (current warp may be waiting on others)
        if self.all_halted():
            self.log.warn("All warps are halted. Stepping a single warp may cause deadlock.")
        
        self._dmreg_write(DMReg.DCTRL, 1, "stepreq")

        # Wait for stepstate to go to 0 (idle)
        with timeout(TIMEOUT, "Timeout waiting for step to complete"):
            while True:
                stepstate = self._dmreg_read(DMReg.DCTRL, "stepstate")
                if stepstate is None:
                    return False
                if stepstate == 0:
                    break
                sleep(TIMESTEP)
        self.selected_warp_pc = self._dmreg_read(DMReg.DPC)
        self.log.debug(f"Warp {self.selected_wid} stepped to PC=0x{self.selected_warp_pc:X}")
        return True

    def read_reg(self, regname):
        def read_arch_reg(regname):
            # Inject instruction to read the register into dscratch
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, {regname}"))
            return self._dmreg_read(DMReg.DSCRATCH, "data")
        
        def read_csr_reg(regname):
            # Inject instruction to read t0, in dscratch
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t0"))
            t0_val = self._dmreg_read(DMReg.DSCRATCH, "data")
            # Inject instruction to read the CSR into t0
            self.inject_instr(rvassemble(f"csrr t0, {regname}"))
            # Inject instruction to write t0 into dscratch
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t0"))
            value = self._dmreg_read(DMReg.DSCRATCH, "data")
            # Inject instruction to restore t0
            self._dmreg_write(DMReg.DSCRATCH, t0_val, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
            return value

        # Make sure warp,thread is selected
        if not self.__assert_warpthread_selected():
            return False

        if regname  == "pc":
            return self._dmreg_read(DMReg.DPC, "pc")
        elif regname in RVREGS or regname.startswith("x"):
            if regname.startswith("x") and not (0 <= int(regname[1:]) < 32):
                self.log.error(f"Invalid register name '{regname}'")
                return None
            
            val = read_arch_reg(regname)
            if val is None:
                self.log.error(f"Failed to read register '{regname}'")
                return None
            return val
        elif regname in RVCSRS:
            csraddr = RVCSRS[regname]
            if isinstance(csraddr, list):
                value = 0
                for i, addr in enumerate(csraddr):
                    v = read_csr_reg(addr)
                    if v is None:
                        self.log.error(f"Failed to read CSR '{regname}' part {i}")
                        return None
                    value |= v << (i * 32)
                return value
            else:
                val = read_csr_reg(csraddr)
                if val is None:
                    self.log.error(f"Failed to read CSR '{regname}'")
                    return None
                return val
        else:
            self.log.error(f"Unknown register '{regname}'")
            return None

    def read_regs(self, regs=[]):
        if not regs:
            regs = self._get_regnames()
        values = {}
        for reg in regs:
            values[reg] = self.read_reg(reg)
        return values
    
    def write_reg(self, regname, value):
        def write_arch_reg(regname, value):
            # Inject instruction to write the register from dscratch
            self._dmreg_write(DMReg.DSCRATCH, value, "data")
            self.inject_instr(rvassemble(f"csrr {regname}, {RVCSRS['vx_dscratch']}"))
        
        def write_csr_reg(regname, value):
            # Inject instruction to read t0, in dscratch
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t0"))
            t0_val = self._dmreg_read(DMReg.DSCRATCH, "data")
            # Inject instruction to read writevalue into t0
            self._dmreg_write(DMReg.DSCRATCH, value, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
            # Inject instruction to write t0 into the CSR
            self.inject_instr(rvassemble(f"csrw {regname}, t0"))
            # Inject instruction to restore t0
            self._dmreg_write(DMReg.DSCRATCH, t0_val, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
        

        # Make sure warp,thread is selected
        if not self.__assert_warpthread_selected():
            return False

        if regname  == "pc":
            return self._dmreg_write(DMReg.DPC, value, "pc")
        elif regname in RVREGS or regname.startswith("x"):
            if regname.startswith("x") and not (0 <= int(regname[1:]) < 32):
                self.log.error(f"Invalid register name '{regname}'")
                return False
            
            write_arch_reg(regname, value)
            return True
        elif regname in RVCSRS:
            csraddr = RVCSRS[regname]
            if isinstance(csraddr, list):
                for i, addr in enumerate(csraddr):
                    part = (value >> (i * 32)) & 0xFFFFFFFF
                    write_csr_reg(addr, part)
                return True
            else:
                write_csr_reg(csraddr, value)
                return True
        else:
            self.log.error(f"Unknown register '{regname}'")
            return False

    def read_mem(self, addr, nbytes):
        # Make sure warp,thread is selected
        if not self.__assert_warpthread_selected():
            return False
        
        if nbytes <= 0:
            self.log.error("Memory read length must be positive.")
            return None

        data = bytearray()

        # --- Save t0 and t1 ---
        self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t0"))
        t0_val = self._dmreg_read(DMReg.DSCRATCH, "data")
        self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t1"))
        t1_val = self._dmreg_read(DMReg.DSCRATCH, "data")

        # --- Compute word-aligned bounds ---
        start_addr = addr & ~0x3
        end_addr   = (addr + nbytes + 3) & ~0x3   # round up to multiple of 4

        # --- Init t0 with start address ---
        self._dmreg_write(DMReg.DSCRATCH, start_addr, "data")
        self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))

        # --- Read full words ---
        for cur in range(start_addr, end_addr, 4):
            self.inject_instr(rvassemble("lw t1, 0(t0)"))
            self.inject_instr(rvassemble("addi t0, t0, 4"))
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t1"))
            val = self._dmreg_read(DMReg.DSCRATCH, "data") or 0
            data += val.to_bytes(4, 'little')

        # --- Restore t0 and t1 ---
        self._dmreg_write(DMReg.DSCRATCH, t0_val, "data")
        self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
        self._dmreg_write(DMReg.DSCRATCH, t1_val, "data")
        self.inject_instr(rvassemble(f"csrr t1, {RVCSRS['vx_dscratch']}"))

        # --- Trim extra head/tail bytes ---
        head_off = addr - start_addr
        return data[head_off : head_off + nbytes]

    def write_mem(self, addr, data: bytes):
        # Make sure warp,thread is selected
        if not self.__assert_warpthread_selected():
            return False
        
        if not data:
            self.log.error("No data to write.")
            return False

        nbytes = len(data)
        end_addr = addr + nbytes

        # --- Save t0 and t1 ---
        self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t0"))
        t0_val = self._dmreg_read(DMReg.DSCRATCH, "data")
        self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t1"))
        t1_val = self._dmreg_read(DMReg.DSCRATCH, "data")

        cur = addr
        idx = 0

        # --- Leading partial word ---
        if cur % 4 != 0:
            base = cur & ~0x3
            self._dmreg_write(DMReg.DSCRATCH, base, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
            self.inject_instr(rvassemble("lw t1, 0(t0)"))
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t1"))
            orig = self._dmreg_read(DMReg.DSCRATCH, "data") or 0
            word = bytearray(orig.to_bytes(4, 'little'))

            off = cur % 4
            take = min(4 - off, nbytes)
            word[off:off+take] = data[idx:idx+take]

            val = int.from_bytes(word, 'little')
            self._dmreg_write(DMReg.DSCRATCH, val, "data")
            self.inject_instr(rvassemble(f"csrr t1, {RVCSRS['vx_dscratch']}"))
            self._dmreg_write(DMReg.DSCRATCH, base, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
            self.inject_instr(rvassemble("sw t1, 0(t0)"))

            cur += take
            idx += take

        # --- Middle full words ---
        while (end_addr - cur) >= 4:
            val = int.from_bytes(data[idx:idx+4], 'little')
            self._dmreg_write(DMReg.DSCRATCH, val, "data")
            self.inject_instr(rvassemble(f"csrr t1, {RVCSRS['vx_dscratch']}"))
            self.inject_instr(rvassemble("sw t1, 0(t0)"))
            self.inject_instr(rvassemble("addi t0, t0, 4"))
            cur += 4
            idx += 4

        # --- Trailing partial word ---
        if cur < end_addr:
            base = cur & ~0x3
            self._dmreg_write(DMReg.DSCRATCH, base, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
            self.inject_instr(rvassemble("lw t1, 0(t0)"))
            self.inject_instr(rvassemble(f"csrw {RVCSRS['vx_dscratch']}, t1"))
            orig = self._dmreg_read(DMReg.DSCRATCH, "data") or 0
            word = bytearray(orig.to_bytes(4, 'little'))

            take = end_addr - cur
            word[0:take] = data[idx:idx+take]

            val = int.from_bytes(word, 'little')
            self._dmreg_write(DMReg.DSCRATCH, val, "data")
            self.inject_instr(rvassemble(f"csrr t1, {RVCSRS['vx_dscratch']}"))
            self._dmreg_write(DMReg.DSCRATCH, base, "data")
            self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
            self.inject_instr(rvassemble("sw t1, 0(t0)"))

        # --- Restore t0 and t1 ---
        self._dmreg_write(DMReg.DSCRATCH, t0_val, "data")
        self.inject_instr(rvassemble(f"csrr t0, {RVCSRS['vx_dscratch']}"))
        self._dmreg_write(DMReg.DSCRATCH, t1_val, "data")
        self.inject_instr(rvassemble(f"csrr t1, {RVCSRS['vx_dscratch']}"))

        return True

    def inject_instr(self, instr, force_select=False):
        # Make sure warp,thread is selected
        if not self.__assert_warpthread_selected():
            return False
        
        if force_select:
            self.select_a_warp(self.selected_wid)
            self.select_a_thread(self.selected_tid)
        self._dmreg_write(DMReg.INJECT, instr, "instr")
        self._dmreg_write(DMReg.DCTRL, 1, "injectreq")
        
        # Wait for injectstate to go to 0 (idle)
        with timeout(TIMEOUT, "Timeout waiting for inject to complete"):
            while True:
                injectstate = self._dmreg_read(DMReg.DCTRL, "injectstate")
                if injectstate is None:
                    return False
                if injectstate == 0:
                    break
                sleep(TIMESTEP)

        self.log.debug(f"Injected instruction (wid: {self.selected_wid}, tid: {self.selected_tid}): 0x{instr:X}")
        return True

    def set_breakpoint(self, addr):
        """
        Set a breakpoint at the given address.
        """
        self.breakpoints[addr] = True
        return True

    def delete_breakpoint(self, addr):
        """
        Clear a breakpoint at the given address.
        """
        self.breakpoints.pop(addr, None)
        return True

    def get_breakpoints(self):
        """
        Get all breakpoints.
        """
        return list(self.breakpoints.keys())
        
    
    def continue_until_break(self):
        """
        Continue execution until a breakpoint is hit.
        """
        if not self.__assert_warpthread_selected():
            return False

        while True:
            # Step the warp
            if not self.step_warp():
                return False
            
            # Check if PC is at a breakpoint
            if self.selected_warp_pc in self.breakpoints:
                self.log.info(f"Hit breakpoint at 0x{self.selected_warp_pc:X} (wid: {self.selected_wid}, tid: {self.selected_tid})")
                return True
   

    ############################################################################
