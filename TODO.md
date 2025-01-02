- adding libraries to project is possible, but it is for now only in the yml file, not in the cmake, thus, useless in a way. Make it usable for real.
- make a command to execute a test or an example (single file) in respective folders as an inline code with no build configuration and no artifacts. (example: `nf example ex1` would execute `examples/ex1.cpp`. `nf test foo` would execute `tests/foo.cpp`)

- make a project default to 1 solution, but can with configuration split and manage multiple sub-solutions in the same project.
    - for instance, a part for core development of a library, and a part for testing, using that built library.