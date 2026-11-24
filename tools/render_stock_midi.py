import ctypes as C
import pathlib
import sys
import wave

L=C.CDLL("libfluidsynth.so.3")
P=C.c_void_p
I=C.c_int
S=C.c_char_p
D=C.c_double

def bind(name,ret,*arguments):
    f=getattr(L,name); f.restype=ret; f.argtypes=arguments
    return f

def render(source, dest, font, rate=32000):
    settings=bind("new_fluid_settings",P)()
    num=bind("fluid_settings_setnum",I,P,S,D)
    string=bind("fluid_settings_setstr",I,P,S,S)
    num(settings,b"synth.sample-rate",rate)
    num(settings,b"synth.gain",.85)
    string(settings,b"player.timing-source",b"sample")
    synth=bind("new_fluid_synth",P,P)(settings)
    load=bind("fluid_synth_sfload",I,P,S,I)
    assert load(synth,bytes(font),1)>=0
    player=bind("new_fluid_player",P,P)(synth)
    assert bind("fluid_player_add",I,P,S)(player,bytes(source))==0
    status=bind("fluid_player_get_status",I,P)
    frames=1024
    audio=(C.c_int16*(frames*2))()
    play=bind("fluid_synth_write_s16",I,P,I,P,I,I,P,I,I)
    assert bind("fluid_player_play",I,P)(player)==0
    n=0
    with wave.open(str(dest),"wb") as file:
        file.setparams((2,2,rate,0,"NONE","not compressed"))
        while status(player)==1:
            assert play(synth,frames,audio,0,2,audio,1,2)==0
            file.writeframesraw(bytes(audio))
            n+=frames
            assert n<rate*600,"Refusing unexpectedly long or unbounded MIDI track"
        assert n>rate,"No track rendered"
    bind("delete_fluid_player",None,P)(player)
    bind("delete_fluid_synth",None,P)(synth)
    bind("delete_fluid_settings",None,P)(settings)
    return n/rate

if __name__=="__main__":
    d,s,f=map(pathlib.Path,sys.argv[1:4])
    print(render(s,d,f))
