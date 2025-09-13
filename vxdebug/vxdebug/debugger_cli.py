from vxdebug.utils import *
from vxdebug.debugger import VortexDebugger


DEFAULT_DBGSERVER_PORT = 3333

BANNER = f"""
+--------------------------------------------------------------------------+
| Vortex Debugger                                                          |
| Copyright © 2019-2023                                                    |
|                                                                          |
| Licensed under the Apache License, Version 2.0 (the "License");          |
| you may not use this file except in compliance with the License.         |
| You may obtain a copy of the License at                                  |
| http://www.apache.org/licenses/LICENSE-2.0                               |
|                                                                          |
| Unless required by applicable law or agreed to in writing, software      |
| distributed under the License is distributed on an "AS IS" BASIS,        |
| WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. |
| See the License for the specific language governing permissions and      |
| limitations under the License.                                           |
+--------------------------------------------------------------------------+
"""


def main():
    import argparse
    parser = argparse.ArgumentParser(description="Vortex Debugger CLI")
    parser.add_argument("-p", "--tcp", help="Connect via TCP (host:port)", type=str, default=None)
    parser.add_argument("-v", "--verbosity", help="Set verbosity level (0:error, 1:warn, 2:info, 3-5:debug)", type=int, choices=range(0,6), default=2)
    parser.add_argument("--no-banner", help="Suppress banner display", action="store_true")
    args = parser.parse_args()

    # Set verbosity level
    Logger.set_verbosity(args.verbosity)

    # Display banner
    if not args.no_banner:
        print(f"{ANSI_YLW}{BANNER}{ANSI_RST}")

    dbg = VortexDebugger()

    if args.tcp:       
        dbg.connect_tcp(hostportstr=args.tcp)

    dbg.run_cli()


if __name__ == "__main__":
    main()