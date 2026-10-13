#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "json"
require "pathname"
require "yaml"

class ComboCatalog
  ROOT = Pathname.new(__dir__).join("..").expand_path
  CATALOG_PATH = ROOT.join("combinations", "catalog.json")
  FLAVOR_ORDER = %w[default rpi vaapi cuda].freeze
  WORKFLOWS = [
    {
      "channel" => "main",
      "path" => ROOT.join(".github", "workflows", "build_bundle.yaml")
    },
    {
      "channel" => "dev",
      "path" => ROOT.join(".github", "workflows", "build_bundle_dev.yaml")
    }
  ].freeze

  def initialize
    @makefile_mapping = parse_makefile_mapping
    @local_ui = parse_local_ui
    @local_core_version = parse_local_core_version
  end

  def generate
    {
      "schema_version" => 1,
      "source_workflows" => WORKFLOWS.map { |workflow| relative_path(workflow.fetch("path")) },
      "entries" => entries
    }
  end

  def entries
    @entries ||= WORKFLOWS.flat_map do |workflow|
      load_workflow_entries(workflow).map do |entry|
        build_entry(workflow.fetch("channel"), relative_path(workflow.fetch("path")), entry)
      end
    end.sort_by do |entry|
      [channel_order(entry.fetch("channel")), flavor_order(entry.fetch("flavor"))]
    end
  end

  def list(catalog = generate)
    catalog.fetch("entries").each do |entry|
      puts [
        entry.fetch("id"),
        "status=#{entry.fetch("status")}",
        "flavor=#{entry.fetch("flavor")}",
        "tags=#{entry.fetch("upstream_tags").join("; ")}",
        "platforms=#{entry.fetch("platforms").join(",") }"
      ].join("  ")
    end
  end

  def show(combo_id, catalog = generate)
    entry = catalog.fetch("entries").find { |candidate| candidate.fetch("id") == combo_id }
    abort "Unknown combo '#{combo_id}'. Known combos: #{catalog.fetch("entries").map { |candidate| candidate.fetch("id") }.join(", ")}" unless entry

    local_workspace = entry.fetch("local_workspace")
    local_ffmpeg = local_workspace.fetch("ffmpeg")
    makefile = local_workspace.fetch("makefile")

    puts "id: #{entry.fetch("id")}"
    puts "status: #{entry.fetch("status")}"
    puts
    puts "upstream"
    puts "  channel: #{entry.fetch("channel")}"
    puts "  flavor: #{entry.fetch("flavor")}"
    puts "  ui: #{entry.fetch("ui")}"
    puts "  core: #{entry.fetch("core")}"
    puts "  ffmpeg: #{entry.fetch("ffmpeg")}"
    puts "  platforms: #{entry.fetch("platforms").join(",")}"
    puts "  source_workflow: #{entry.fetch("source_workflow")}"
    puts "  tag_prefix_or_name: #{display_tag_prefix_or_name(entry.fetch("tag_prefix_or_name"))}"
    puts "  upstream_tags:"
    entry.fetch("upstream_tags").each do |tag|
      puts "    - #{tag}"
    end
    puts
    puts "local_workspace"
    puts "  ffmpeg_flavor: #{local_workspace.fetch("ffmpeg_flavor")}"
    puts "  core_build_image: #{makefile.fetch("core_build_image")}"
    puts "  core_golang_image: #{makefile.fetch("core_golang_image")}"
    puts "  ui: #{local_workspace.fetch("ui").fetch("version")} (bundle #{local_workspace.fetch("ui").fetch("bundle")})"
    puts "  core: #{local_workspace.fetch("core").fetch("version")}"
    puts "  ffmpeg: #{ffmpeg_summary(local_ffmpeg)}"
    puts "  ffmpeg_dockerfile: #{local_ffmpeg.fetch("dockerfile")}"
    puts "  ffmpeg_build_image: #{local_ffmpeg.fetch("build_image")}"
    print_markers("drift_markers", entry.fetch("drift_markers"))
    print_markers("manual_review_markers", entry.fetch("manual_review_markers"))
  end

  private

  def load_workflow_entries(workflow)
    workflow_data = YAML.safe_load(File.read(workflow.fetch("path")), aliases: true)
    workflow_data.fetch("jobs").fetch("docker").fetch("strategy").fetch("matrix").fetch("include")
  end

  def build_entry(channel, source_workflow, entry)
    flavor = infer_flavor(channel, entry)
    ui = normalize_ui(channel, entry.fetch("ui"))
    core = normalize_core(entry.fetch("core"))
    ffmpeg = entry.fetch("ffmpeg")
    local_workspace = build_local_workspace(flavor)
    drift_markers, manual_review_markers = compare_with_local_workspace(ui, core, ffmpeg, local_workspace)

    {
      "id" => "#{channel}/#{flavor}",
      "channel" => channel,
      "flavor" => flavor,
      "ui" => ui,
      "core" => core,
      "ffmpeg" => ffmpeg,
      "platforms" => parse_platforms(entry.fetch("platforms")),
      "source_workflow" => source_workflow,
      "tag_prefix_or_name" => tag_prefix_or_name(channel, entry),
      "upstream_tags" => build_upstream_tags(channel, entry, core, ffmpeg),
      "status" => overall_status(drift_markers, manual_review_markers),
      "drift_markers" => drift_markers,
      "manual_review_markers" => manual_review_markers,
      "local_workspace" => local_workspace
    }
  end

  def infer_flavor(channel, entry)
    return entry.fetch("name") == "dev" ? "default" : entry.fetch("name").sub(/-dev\z/, "") if channel == "dev"

    prefix = entry.fetch("prefix", "").to_s
    return "default" if prefix.empty?

    prefix.delete_suffix("-")
  end

  def normalize_ui(channel, value)
    return "latest resolved in workflow" if channel == "main" && value.include?("${{")

    value
  end

  def normalize_core(value)
    value.gsub("${{ needs.versions.outputs.coreversion }}", "<version>")
  end

  def parse_platforms(value)
    value.split(",").map(&:strip)
  end

  def tag_prefix_or_name(channel, entry)
    channel == "main" ? entry.fetch("prefix", "").to_s : entry.fetch("name")
  end

  def build_upstream_tags(channel, entry, core, ffmpeg)
    if channel == "main"
      prefix = entry.fetch("prefix", "").to_s
      [
        "#{prefix}<bundle-version>-ui<ui-version>-#{core}-#{ffmpeg}",
        "#{prefix}<bundle-version>",
        "#{prefix}latest"
      ]
    else
      [entry.fetch("name")]
    end
  end

  def build_local_workspace(flavor)
    mapping = @makefile_mapping.fetch(flavor)

    {
      "ffmpeg_flavor" => flavor,
      "ui" => @local_ui,
      "core" => {
        "version" => @local_core_version
      },
      "ffmpeg" => {
        "version" => @makefile_mapping.fetch("ffmpeg_version"),
        "os_name" => mapping.fetch("os_name"),
        "os_version" => mapping.fetch("os_version"),
        "cuda_version" => mapping["cuda_version"],
        "dockerfile" => mapping.fetch("dockerfile"),
        "build_image" => mapping.fetch("build_image")
      },
      "makefile" => {
        "core_build_image" => mapping.fetch("core_build_image"),
        "core_golang_image" => @makefile_mapping.fetch("core_golang_image")
      }
    }
  end

  def compare_with_local_workspace(ui, core, ffmpeg, local_workspace)
    drift_markers = []
    manual_review_markers = []

    compare_ui(ui, local_workspace.fetch("ui"), drift_markers, manual_review_markers)
    compare_core(core, local_workspace, drift_markers, manual_review_markers)
    compare_ffmpeg(ffmpeg, local_workspace.fetch("ffmpeg"), drift_markers)

    [drift_markers, manual_review_markers]
  end

  def compare_ui(upstream_ui, local_ui, drift_markers, manual_review_markers)
    case upstream_ui
    when "dev"
      drift_markers << "UI drift: upstream uses dev while the local workspace is pinned to #{local_ui.fetch("version")} (bundle #{local_ui.fetch("bundle")})."
    when "latest resolved in workflow"
      manual_review_markers << "UI version is resolved by the upstream workflow at build time; the local workspace is pinned to #{local_ui.fetch("version")} (bundle #{local_ui.fetch("bundle")})."
    else
      return if upstream_ui == local_ui.fetch("version")

      drift_markers << "UI drift: upstream uses #{upstream_ui} while the local workspace is pinned to #{local_ui.fetch("version")}."
    end
  end

  def compare_core(upstream_core, local_workspace, drift_markers, manual_review_markers)
    metadata = parse_core_metadata(upstream_core)
    local_core_version = local_workspace.fetch("core").fetch("version")
    local_core_image = local_workspace.fetch("makefile").fetch("core_build_image")

    case metadata.fetch("version_kind")
    when "dev"
      drift_markers << "Core drift: upstream uses #{upstream_core} while the local workspace is pinned to #{local_core_version}."
    when "dynamic"
      manual_review_markers << "Core version is resolved by the upstream workflow at build time; the local workspace is pinned to #{local_core_version}."
    when "release"
      return if metadata.fetch("version") == local_core_version && metadata.fetch("build_image") == local_core_image

      drift_markers << "Core drift: upstream uses #{upstream_core} while the local workspace is pinned to #{local_core_version} with #{local_core_image}."
    end

    return if metadata.fetch("build_image") == local_core_image

    drift_markers << "Core build base drift: upstream uses #{metadata.fetch("build_image")} while the local Makefile maps #{local_workspace.fetch("ffmpeg_flavor")} to #{local_core_image}."
  end

  def compare_ffmpeg(upstream_ffmpeg, local_ffmpeg, drift_markers)
    metadata = parse_ffmpeg_metadata(upstream_ffmpeg)
    local_base = "#{local_ffmpeg.fetch("os_name")}#{local_ffmpeg.fetch("os_version")}"

    if metadata.fetch("version") != local_ffmpeg.fetch("version")
      drift_markers << "FFmpeg drift: upstream uses #{metadata.fetch("version")} while the local Makefile pins #{local_ffmpeg.fetch("version")}."
    end

    if metadata.fetch("os_name") != local_ffmpeg.fetch("os_name") || metadata.fetch("os_version") != local_ffmpeg.fetch("os_version")
      drift_markers << "FFmpeg base drift: upstream uses #{metadata.fetch("os_name")}#{metadata.fetch("os_version")} while the local Makefile pins #{local_base}."
    end

    return if metadata.fetch("cuda_version") == local_ffmpeg["cuda_version"]

    drift_markers << "CUDA toolchain drift: upstream uses #{metadata.fetch("cuda_version") || "no CUDA suffix"} while the local Makefile pins #{local_ffmpeg["cuda_version"] || "no CUDA suffix"}."
  end

  def parse_core_metadata(value)
    if (match = value.match(/^core(?<version>\d+\.\d+\.\d+)-(?<os_name>[a-z]+)(?<os_version>\d+(?:\.\d+)*)$/))
      return {
        "version_kind" => "release",
        "version" => match[:version],
        "build_image" => "#{match[:os_name]}:#{match[:os_version]}"
      }
    end

    if (match = value.match(/^core<version>-(?<os_name>[a-z]+)(?<os_version>\d+(?:\.\d+)*)$/))
      return {
        "version_kind" => "dynamic",
        "version" => nil,
        "build_image" => "#{match[:os_name]}:#{match[:os_version]}"
      }
    end

    if (match = value.match(/^core-dev-(?<os_name>[a-z]+)(?<os_version>\d+(?:\.\d+)*)$/))
      return {
        "version_kind" => "dev",
        "version" => "dev",
        "build_image" => "#{match[:os_name]}:#{match[:os_version]}"
      }
    end

    abort "Unsupported core tag format: #{value}"
  end

  def parse_ffmpeg_metadata(value)
    match = value.match(/^ffmpeg(?<version>\d+\.\d+\.\d+)(?:-(?<variant>rpi|vaapi|cuda))?-(?<os_name>[a-z]+)(?<os_version>\d+(?:\.\d+)*)(?:-cuda(?<cuda_version>\d+\.\d+\.\d+))?$/)
    abort "Unsupported ffmpeg tag format: #{value}" unless match

    {
      "version" => match[:version],
      "variant" => match[:variant] || "default",
      "os_name" => match[:os_name],
      "os_version" => match[:os_version],
      "cuda_version" => match[:cuda_version]
    }
  end

  def parse_local_ui
    package = JSON.parse(File.read(ROOT.join("third_party", "restreamer-ui", "package.json")))
    bundle = package.fetch("bundle")

    {
      "version" => package.fetch("version"),
      "bundle" => bundle,
      "bundle_version" => bundle.sub(/^restreamer-v/, "")
    }
  end

  def parse_local_core_version
    contents = File.read(ROOT.join("third_party", "core", "app", "version.go"))
    parts = %w[Major Minor Patch].map do |name|
      match = contents.match(/^\s*#{name}:\s*(\d+),$/)
      abort "Could not parse #{name} from third_party/core/app/version.go" unless match

      match[1]
    end

    parts.join(".")
  end

  def parse_makefile_mapping
    mapping = {}
    current_flavor = nil

    File.read(ROOT.join("Makefile")).each_line do |line|
      if (match = line.match(/^ifeq \(\$\(FFMPEG_FLAVOR\),([^)]+)\)$/))
        current_flavor = match[1]
        mapping[current_flavor] ||= {}
        next
      end

      if (match = line.match(/^else ifeq \(\$\(FFMPEG_FLAVOR\),([^)]+)\)$/))
        current_flavor = match[1]
        mapping[current_flavor] ||= {}
        next
      end

      current_flavor = nil if line.match?(/^endif$/)

      if (match = line.match(/^FFMPEG_VERSION\s*\?=\s*(.+)$/))
        mapping["ffmpeg_version"] = match[1].strip
        next
      end

      if (match = line.match(/^CORE_GOLANG_IMAGE\s*:=\s*(.+)$/))
        mapping["core_golang_image"] = match[1].strip
        next
      end

      next unless current_flavor

      if (match = line.match(/^(FFMPEG_DOCKERFILE|FFMPEG_OS_NAME|FFMPEG_OS_VERSION|FFMPEG_CUDA_VERSION|FFMPEG_BUILD_IMAGE|CORE_BUILD_IMAGE)\s*:=\s*(.+)$/))
        key = match[1]
        value = match[2].strip
        apply_makefile_mapping(mapping[current_flavor], key, value)
      end
    end

    FLAVOR_ORDER.each do |flavor|
      abort "Missing Makefile mapping for #{flavor}" unless mapping.key?(flavor)

      %w[dockerfile os_name os_version build_image core_build_image].each do |key|
        abort "Missing #{key} for flavor #{flavor} in Makefile" unless mapping.fetch(flavor).key?(key)
      end
    end
    abort "Missing FFMPEG_VERSION in Makefile" unless mapping.key?("ffmpeg_version")
    abort "Missing CORE_GOLANG_IMAGE in Makefile" unless mapping.key?("core_golang_image")

    mapping
  end

  def apply_makefile_mapping(flavor_mapping, key, value)
    case key
    when "FFMPEG_DOCKERFILE"
      flavor_mapping["dockerfile"] = "third_party/ffmpeg/#{value}"
    when "FFMPEG_OS_NAME"
      flavor_mapping["os_name"] = value
    when "FFMPEG_OS_VERSION"
      flavor_mapping["os_version"] = value
    when "FFMPEG_CUDA_VERSION"
      flavor_mapping["cuda_version"] = value
    when "FFMPEG_BUILD_IMAGE"
      flavor_mapping["build_image"] = value
    when "CORE_BUILD_IMAGE"
      flavor_mapping["core_build_image"] = value
    end
  end

  def overall_status(drift_markers, manual_review_markers)
    return "drift" unless drift_markers.empty?
    return "manual_review" unless manual_review_markers.empty?

    "aligned"
  end

  def ffmpeg_summary(local_ffmpeg)
    summary = "#{local_ffmpeg.fetch("version")} on #{local_ffmpeg.fetch("os_name")}#{local_ffmpeg.fetch("os_version")}"
    return summary unless local_ffmpeg["cuda_version"]

    "#{summary} with CUDA #{local_ffmpeg.fetch("cuda_version")}"
  end

  def print_markers(label, markers)
    puts
    puts label
    if markers.empty?
      puts "  - none"
      return
    end

    markers.each do |marker|
      puts "  - #{marker}"
    end
  end

  def display_tag_prefix_or_name(value)
    value.empty? ? "<empty prefix>" : value
  end

  def relative_path(path)
    Pathname.new(path).relative_path_from(ROOT).to_s
  end

  def channel_order(channel)
    channel == "main" ? 0 : 1
  end

  def flavor_order(flavor)
    FLAVOR_ORDER.index(flavor) || FLAVOR_ORDER.length
  end
end

def load_catalog(path)
  JSON.parse(File.read(path))
end

def write_catalog(path, catalog)
  FileUtils.mkdir_p(File.dirname(path))
  File.write(path, JSON.pretty_generate(catalog) + "\n")
end

def usage
  <<~USAGE
    Usage:
      ruby scripts/generate_combo_catalog.rb generate [output_path]
      ruby scripts/generate_combo_catalog.rb list [catalog_path]
      ruby scripts/generate_combo_catalog.rb show <combo_id> [catalog_path]
  USAGE
end

catalog = ComboCatalog.new
command = ARGV.shift || "generate"

case command
when "generate"
  output_path = ARGV.shift || ComboCatalog::CATALOG_PATH.to_s
  write_catalog(output_path, catalog.generate)
when "list"
  catalog_path = ARGV.shift || ComboCatalog::CATALOG_PATH.to_s
  catalog.list(load_catalog(catalog_path))
when "show"
  combo_id = ARGV.shift
  abort usage unless combo_id

  catalog_path = ARGV.shift || ComboCatalog::CATALOG_PATH.to_s
  catalog.show(combo_id, load_catalog(catalog_path))
else
  abort usage
end
