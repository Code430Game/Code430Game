import sys

from pack_tools.validate import main

if sys.argv[1:3] == ["version", "check"]:
    from pack_tools.versions import main as version_main

    raise SystemExit(version_main(sys.argv[3:]))
if sys.argv[1:2] == ["lock"]:
    from pack_tools.lock import main as lock_main

    raise SystemExit(lock_main(sys.argv[2:]))
raise SystemExit(main())
