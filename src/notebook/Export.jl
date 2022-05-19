import Pkg
using Base64
using HypertextLiteral

const default_binder_url = "https://mybinder.org/v2/gh/fonsp/pluto-on-binder/v$(string(PLUTO_VERSION))"

const cdn_version_override = nothing
# const cdn_version_override = "2a48ae2"

if cdn_version_override !== nothing
    @warn "Reminder to fonsi: Using a development version of Pluto for CDN assets. The binder button might not work. You should not see this on a released version of Pluto." cdn_version_override
end

"""
See [PlutoSliderServer.jl](https://github.com/JuliaPluto/PlutoSliderServer.jl) if you are interested in exporting notebooks programatically.
"""
function generate_html(;
        version::Union{Nothing,VersionNumber,AbstractString}=nothing, 
        pluto_cdn_root::Union{Nothing,AbstractString}=nothing,
        
        notebookfile_js::AbstractString="undefined", 
        statefile_js::AbstractString="undefined", 
        
        slider_server_url_js::AbstractString="undefined", 
        binder_url_js::AbstractString=repr(default_binder_url),
        
        disable_ui::Bool=true, 
        preamble_html_js::AbstractString="undefined",
        notebook_id_js::AbstractString="undefined", 
        isolated_cell_ids_js::AbstractString="undefined",
        
        header_html::AbstractString="",
    )::String

    # Here we don't use frontend-dist (bundled code) yet, might want to
    # use a separate Parcel pipeline to make UBER-BUNDLED html exports (TODO DRAL)
    original = read(project_relative_path("frontend", "editor.html"), String)

    cdn_root = if pluto_cdn_root === nothing
        if version === nothing
            version = PLUTO_VERSION
        end
        "https://cdn.jsdelivr.net/gh/fonsp/Pluto.jl@$(something(cdn_version_override, string(PLUTO_VERSION)))/frontend/"
    else
        pluto_cdn_root
    end

    @debug "Using CDN for Pluto assets:" cdn_root

    cdnified = replace(
        replace(original, 
        "href=\"./" => "href=\"$(cdn_root)"),
        "src=\"./" => "src=\"$(cdn_root)")

    result = replace_at_least_once(
        replace_at_least_once(cdnified, 
            "<meta name=\"pluto-insertion-spot-meta\">" => 
            """
            $(header_html)
            <meta name=\"pluto-insertion-spot-meta\">
            """),
        "<meta name=\"pluto-insertion-spot-parameters\">" => 
        """
        <script data-pluto-file="launch-parameters">
        window.pluto_notebook_id = $(notebook_id_js);
        window.pluto_isolated_cell_ids = $(isolated_cell_ids_js);
        window.pluto_notebookfile = $(notebookfile_js);
        window.pluto_disable_ui = $(disable_ui ? "true" : "false");
        window.pluto_slider_server_url = $(slider_server_url_js);
        window.pluto_binder_url = $(binder_url_js);
        window.pluto_statefile = $(statefile_js);
        window.pluto_preamble_html = $(preamble_html_js);
        </script>
        <meta name=\"pluto-insertion-spot-parameters\">
        """
    )

    return result
end

function replace_at_least_once(s, pair)
    from, to = pair
    @assert occursin(from, s)
    replace(s, pair)
end


function generate_html(notebook; kwargs...)::String
    state = notebook_to_js(notebook)

    notebookfile_js = let
        notebookfile64 = base64encode() do io
            save_notebook(io, notebook)
        end

        "\"data:text/julia;charset=utf-8;base64,$(notebookfile64)\""
    end

    statefile_js = let
        statefile64 = base64encode() do io
            pack(io, state)
        end

        "\"data:;base64,$(statefile64)\""
    end
    
    fm = frontmatter(notebook)
    header_html = isempty(fm) ? "" : frontmatter_html(fm) # avoid loading HypertextLiteral if there is no frontmatter
    
    # We don't set `notebook_id_js` because this is generated by the server, the option is only there for funky setups.
    generate_html(; statefile_js, notebookfile_js, header_html, kwargs...)
end


const frontmatter_writers = (
    ("title", x -> @htl("""
        <title>$(x)</title>
        """)),
    ("description", x -> @htl("""
        <meta name="description" content=$(x)>
        """)),
    ("tags", x -> x isa Vector ? @htl("$((
        @htl("""
            <meta property="og:article:tag" content=$(t)>
            """)
        for t in x
    ))") : nothing),
)


const _og_properties = ("title", "type", "description", "image", "url", "audio", "video", "site_name", "locale", "locale:alternate", "determiner")

const _default_frontmatter = Dict{String, Any}(
    "type" => "article",
    # Note: these defaults are skipped when there is no frontmatter at all.
)

function frontmatter_html(frontmatter::Dict{String,Any}; default_frontmatter::Dict{String,Any}=_default_frontmatter)::String
    d = merge(default_frontmatter, frontmatter)
    repr(MIME"text/html"(), 
        @htl("""$((
            f(d[key])
            for (key, f) in frontmatter_writers if haskey(d, key)
        ))$((
            @htl("""<meta property=$("og:$(key)") content=$(val)>
            """)
            for (key, val) in d if key in _og_properties
        ))"""))
end
