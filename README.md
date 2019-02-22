# StraightDocker

There's no source code here; it's just a place to store Windows binary releases of Docker.

The main Docker project ([moby/moby](https://github.com/moby/moby)) releases nightly
binaries at https://master.dockerproject.org. However, only the very latest build is
available, generally (there are some ancient builds there; I don't know why). I'm using
this project to host a stable release point of known good builds of the Windows binaries.

A release hosted here may be simply a copy of a master.dockerproject.org nightly build, or
it may consist of privately-built binaries, built from some other branch (such as to pick
up new features and/or bugfixes before they get merged into Moby's master branch, which
can sometimes take a while). The description of a release will tell you what is in it.

It also includes the "wincred" credential helper (docker-credential-wincred.exe) from the
[docker-credential-helpers](https://github.com/docker/docker-credential-helpers) project.

I use the term "straight Docker" to differentiate between "Docker for Windows" (D4W),
which is a closed-source product made by Docker, Inc; and the open-source components from
the Moby project ("straight Docker") which D4W builds upon.

## Sample scripts to "install" it

There are some sample scripts in the `sampleScripts` directory that demonstrate how to
install the "straight docker" binaries: it's mostly just "xcopy", but there are a few
pieces:
 1. Copy docker binaries into `C:\docker`.
 2. Copy LCOW kernel-related binaries (downloaded from
    [linuxkit/lcow](https://github.com/linuxkit/lcow)) into `C:\Program Files\Linux
    Containers`.
 3. Enable container-related Windows features (like Hyper-V).

It's basically just a bit more automation over the top of the steps described on the
[linuxkit/lcow readme](https://github.com/linuxkit/lcow/blob/master/README.md), plus a
stable download instead of "download last night's build".

**Note** that the scripts are not intended to be "production ready"; they are a sample
that you can incorporate or build upon. There are plenty of things that are not handled;
for instance
 * it does not check for an existing installation of D4W;
 * although a .json file with version info is included, there is no facility for detecting
   an older version and upgrading;
 * it is missing proper dependency checks (e.g. it just checks if curl.exe is available to
   decide if your version of Windows is recent enough);
 * etc.

Also **note** again that they will enable Hyper-V and container-related features of
Windows, which may require a reboot (it should tell you if it needs it).

If you just want to try it out real quick, these commands should work (powershell):

```powershell
$url = 'https://github.com/jazzdelightsme/StraightDocker/archive/master.zip'
curl.exe --progress --location -o straightDockerRepo.zip $url
Expand-Archive .\straightDockerRepo.zip
.\straightDockerRepo\StraightDocker-master\sampleScripts\setup.ps1
```

(You don't need to be elevated.)

In a nutshell: it will download this repo, expand it, then run the `setup.ps1` script from
the `sampleScripts` directory, which will ask a couple of questions, then launch an
elevated window to enable windows features, copy an LCOW kernel to ProgramFiles, and put
the docker EXEs in `C:\docker`, and then start the docker daemon (if you already have the
required features enabled; if not, you'll have to reboot first and then run the script
again). If you are running Windows PowerShell instead of PowerShell core (pwsh), then you
will also have to allow some prompts to install the ThreadJob module.

## Should I use this?

"Straight docker" is based on experimental components that are under active development.

Take a look at the "Moby is recommended" versus "Moby is NOT recommended" section of
https://mobyproject.org, and just substitute the phrase "straight docker" in place of
"Moby":

> **Straight docker** is recommended for [...]
>  * Hackers who want to customize or patch their Docker build
>  * System engineers or integrators building a container system
>  * Container enthusiasts who want to experiment with the latest container tech
>  * etc. ...

> **Straight docker** is **NOT** recommended for [...]
>  * Application developers looking for an easy way to run their applications in
>    containers. We recommend Docker CE instead.
>  * Enterprise IT and development teams looking for a ready-to-use, commercially
>    supported container platform. We recommend Docker EE instead.
>  * Anyone curious about containers and looking for an easy way to learn. We recommend
>    the docker.com website instead.

In particular, note that there is no additional testing, QA, validation, etc. that is done
to these binaries other than what happens as part of the Moby nightly build/release
process, other than the fact that I personally got the binaries to run on my machine. And
there's no support other than "go file an issue on the moby project". If you are okay with
that... have fun!

