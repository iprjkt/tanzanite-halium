# Hardware-accelerated OpenGL (gl4es) + libhybris Wayland EGL/GLES
# for standard Linux desktop applications on tanzanite (Mali-G57 MC2).
if [ -d /usr/local/lib/gl4es ]; then
    case ":${LD_LIBRARY_PATH:-}:" in
        *":/usr/local/lib/gl4es:"*) ;;
        *) export LD_LIBRARY_PATH="/usr/local/lib/gl4es${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}" ;;
    esac
fi

export LIBGL_EGL="/usr/lib/aarch64-linux-gnu/libEGL.so.1"
export LIBGL_GLES="/usr/lib/aarch64-linux-gnu/libGLESv2.so.2"
export LIBGL_FB="${LIBGL_FB:-3}"
export LIBGL_ES="${LIBGL_ES:-2}"
export LIBGL_NOBANNER="${LIBGL_NOBANNER:-1}"
export EGL_PLATFORM="${EGL_PLATFORM:-wayland}"
