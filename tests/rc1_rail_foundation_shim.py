"""Common C++ declarations for compiling unmodified RC1 rail commands."""
import re


def source_block(src, file, pattern):
    raw = (src / file).read_text()
    begin = re.search(pattern, raw, re.M).start()
    opening = raw.index("{", begin)
    level = 1
    i = opening + 1
    while level:
        level += (raw[i] == "{") - (raw[i] == "}")
        i += 1
    return raw[begin:i] + (";" if raw[i:i+1] == ";" else "") + "\n"


def rail_foundation_shim(src):
    def block(file, pattern):
        return source_block(src, file, pattern)

    shim = r"""
    #include <array>
    #include <cassert>
    #include <cstdint>
    #include <cstdlib>
    #include <initializer_list>
    #include <iostream>
    #include <type_traits>
    using uint=unsigned;
    using TileIndex=int;
    template<typename E> constexpr auto to_underlying(E e){return static_cast<std::underlying_type_t<E>>(e);}
    #define NOT_REACHED() std::abort()
    template<typename E> constexpr bool IsInsideMM(E i,E a,E b){return a<=i && i<b;}
    constexpr uint TILE_HEIGHT=8;
    """
    for pattern in (r"^enum class Corner :",r"^enum Slope :",r"^enum class Foundation :"):
        shim += block("slope_type.h",pattern)
    shim += r"""
    constexpr Slope operator~(Slope s){return Slope(~int(s));}
    constexpr Slope operator&(Slope a,Slope b){return Slope(int(a)&int(b));}
    constexpr Slope operator|(Slope a,Slope b){return Slope(int(a)|int(b));}
    constexpr Slope operator^(Slope a,Slope b){return Slope(int(a)^int(b));}
    enum class Track {X,Y,Upper,Lower,Left,Right};
    struct TrackBits {
     int n=0;
     constexpr TrackBits()=default;
     constexpr TrackBits(int n):n(n){}
     constexpr TrackBits(Track t):n(1<<int(t)){}
     constexpr TrackBits(std::initializer_list<Track> ts){for(Track t:ts)n|=1<<int(t);}
     constexpr bool None() const{return n==0;}
     constexpr bool Any() const{return n!=0;}
     constexpr bool Any(TrackBits t)const{return (n&t.n)!=0;}
     constexpr TrackBits& Reset(TrackBits t){n&=~t.n;return *this;}
     constexpr int base()const{return n;}
    };
    constexpr TrackBits operator&(TrackBits a,TrackBits b){return a.n&b.n;}
    constexpr TrackBits operator|(TrackBits a,TrackBits b){return a.n|b.n;}
    constexpr bool operator==(TrackBits a,TrackBits b){return a.n==b.n;}
    constexpr TrackBits TRACK_BIT_ALL=63, TRACK_BIT_HORZ=12, TRACK_BIT_VERT=48;
    constexpr bool TracksOverlap(TrackBits t) {
      return t.Any() && (t.n & (t.n-1)) && t.n!=12 && t.n!=48;
    }
    constexpr TrackBits CornerToTrackBits(Corner c) {return std::array{16,8,32,4}[to_underlying(c)];}
    template<class T> using NonSteepSlopeIndexArray=std::array<T,15>;
    """
    for name in ("IsValidCorner", "IsSteepSlope", "IsHalftileSlope", "RemoveHalftileSlope",
                 "ComplementSlope", "IsSlopeWithOneCornerRaised", "SlopeWithOneCornerRaised",
                 "GetHighestSlopeCorner", "OppositeCorner", "IsSlopeWithThreeCornersRaised",
                 "SlopeWithThreeCornersRaised", "HalftileSlope", "IsFoundation", "IsLeveledFoundation",
                 "IsNonContinuousFoundation", "GetHalftileFoundationCorner", "IsSpecialRailFoundation",
                 "GetRailFoundationCorner", "HalftileFoundation", "SpecialRailFoundation"):
        shim += block("slope_func.h",r"^(?:static constexpr |inline )\w+ " + name + r"\(")
    shim += block("rail_cmd.cpp",r"^static constexpr NonSteepSlopeIndexArray<TrackBits> _valid_tracks_without_foundation")
    shim += block("rail_cmd.cpp",r"^static constexpr NonSteepSlopeIndexArray<TrackBits> _valid_tracks_on_leveled_foundation").replace("{{{","{{").replace("}}}","}}")
    shim += block("rail_cmd.cpp",r"^Foundation GetRailFoundation")
    shim += block("landscape.cpp",r"^uint ApplyFoundationToSlope")
    shim += block("rail_map.h",r"^enum class RailGroundType :")
    return shim
