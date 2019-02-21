# StraightDocker

There's no source code here; it's just a place to store Windows binary releases of Docker.

The main Docker project ([moby/moby](https://github.com/moby/moby)) releases nightly binaries at https://master.dockerproject.org. However, only the very latest build is available, generally (there are some ancient builds there; I don't know why). I'm using this project to host a stable release point of known good builds of the Windows binaries.

A release hosted here may be simply a copy of a master.dockerproject.org nightly build, or it may consist of privately-built binaries, built from some other branch (such as to pick up new features and/or bugfixes before they get merged into Moby's master branch, which can sometimes take a while). The description of a release will tell you what is in it.

It also includes the "wincred" credential helper (docker-credential-wincred.exe) from the [docker-credential-helpers](https://github.com/docker/docker-credential-helpers) project.

I use the term "straight Docker" to differentiate between "Docker for Windows" (D4W), which is a closed-source product made by Docker, Inc; and the open-source components from the Moby project ("straight Docker") which D4W builds upon.


