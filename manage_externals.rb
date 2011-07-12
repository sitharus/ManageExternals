#!/usr/bin/env ruby

def process_relative(path, ext, repo_root)
  base, rest = ext.split(/\^/)
  source, target = rest.split(/ /)

  external_path = File.join(path, base, target)
  svn_source = replace_relative(repo_root, source).gsub(/\/$/, '')
  if !update_checkout(external_path, svn_source)
    puts "#{external_path} needs checkout"
  end
  external_path
end

def process_absolute(path, ext)
  target, source = ext.split(/ /)
  external_path = File.join(path, target)
  if !update_checkout(external_path, source)
    puts "#{external_path} needs checkout"
  end
  external_path
end

def replace_relative(root, target)
  if target =~ /^\/\.\./
    replace_relative(root.gsub(/\/[a-zA-Z0-9-]+$/, ''), target.gsub(/^\/\.\./, ''))
  else
    root + target
  end
end

def update_checkout(path, svn_source)
  if File.exists? path
    Dir.chdir(path) do |d|
      info_output = `svn info 2>&1`
      if info_output =~ /is not a working copy/
        puts "Checkout #{svn_source} in to #{path}"
        `svn checkout '#{svn_source}' .`
      else
        svn_info = {}
        info_output.split(/[\r\n]+/).map {|l| l.split(/:/, 2).map {|i| i.strip }}.each {|i| svn_info[i[0]] = i[1]}
        url = svn_info['URL']
        if url != svn_source
          puts "Switching #{path} to #{svn_source}"
          `svn switch '#{svn_source}'`
        else
          puts "Updating #{path}"
          `svn update`
        end
      end
    end
  else
    puts "Checkout #{svn_source} in to #{path}"
    `svn checkout '#{svn_source}' '#{path}'`
  end
  $? == 0
end


path = File.expand_path(ARGV[0])
svn_base = nil
Dir.chdir(path) do |d|
  svn_info = {}
  `git svn info`.split(/[\r\n]+/).map {|l| l.split(/:/, 2).map {|i| i.strip }}.each {|i| svn_info[i[0]] = i[1]}
  svn_base = svn_info['Repository Root']
end

externals = `git svn show-externals`.map {|s| s.strip!}
registered_externals = []
registered_externals_path = File.join(path, '.svn_external_registry')

if File.exists? registered_externals_path
  registered_externals.concat(File.read(registered_externals_path).map {|s| s.strip!}.reject{|s| s.nil? || s.empty?})
end

seen_externals = []

externals.each do |ext|
  case ext
  when /^#/
  when ""
    next
  when /^[^\/]/
    next
  when /\^/
    seen_externals << process_relative(path, ext, svn_base)
  else
    seen_externals << process_absolute(path, ext)
  end
end
seen_externals.reject! {|i| i.nil? or i.strip.empty?}

unseen = registered_externals - seen_externals

if unseen.length > 0
  puts "Externals that are no longer known, consider deleting these:"
  puts unseen.join("\n")
end

File.open(registered_externals_path, 'w') do |f|
  f << seen_externals.join("\n")
end

ignored_files = []
gitignore = File.join(path, '.gitignore')
if File.exists? gitignore
  gitignore = File.read(gitignore).map {|s| s.strip!}
end

gitignore.reject! {|l| registered_externals.include? l}

ignored_files.concat(seen_externals)
File.open(gitignore, 'w') do |f|
  f << ignored_files.join("\n")
end
