#!/usr/bin/env python3
import otool_parse

import sys
import os
import re
import shutil

def otool_library(lib):
  '''Runs otool on the library at lib.
  
  Returns an otool_parse.OtoolParser.
  '''
  otool_file = os.popen('otool -L "' + lib +'"')
  otool_data = otool_file.read()
  return otool_parse.OtoolParser(otool_data)

def recursively_discover_all_dependencies(lib):
  '''Recursively find all dependencies for library at path in lib.
  
  Returns a list of paths.
  '''
  libraries = dict([(l,1) for l in lib])
  old_libraries = {}
  while libraries != old_libraries:
    old_libraries = libraries.copy()
    for lib in list(libraries.keys()):
      dep_parser = otool_library(lib)
      for dep in dep_parser.third_party_shlib_deps():
        libraries[dep] = 1
  return list(old_libraries.keys())

# Three frameworks are addressed inside the application by names that are not the
# ones their files carry, and have been for as long as the bundle has existed.
#
# The file name a GNU library installs holds the library's own number, not its
# release: libgcrypt 1.12.4 installs libgcrypt.20.dylib, libotr 4.1.1 installs
# libotr.5.dylib and libgpg-error 1.61 installs libgpg-error.0.dylib. Read
# straight through, the rules below would name them libgcrypt.framework with a
# Versions/20, libotr.framework with a Versions/5 and libgpg-error.framework with
# a Versions/0. What the application links is libgcrypt.framework,
# libgpgerror.framework and libotr.framework, every one of them with a Versions/A:
# that is what Adium.xcodeproj names, what the load commands in the shipped
# binaries name, and what every released Adium has carried.
#
# So the number is dropped here on purpose instead of being carried through. The
# framework is pinned to Versions/A, which means a release that bumps a library
# number moves nothing the application has to be told about. Going the other way,
# renaming what the application links so that it follows the file name, would
# break every bundle already built for no gain at all.
#
# The key is the name the rules below derive rather than the file name, so it
# survives that bump too.
FRAMEWORK_NAME_OVERRIDES = {
  'libgpg-error': ('libgpgerror', 'A'),
  'libgcrypt':    ('libgcrypt',   'A'),
  'libotr':       ('libotr',      'A'),
}

def lib_path_to_framework_and_version(library_path):
  library_name = library_path.split('/')[-1]
  # check to see if it's a "versionless" library name
  match = re.match(r'[A-Za-z]*\.dylib', library_name)
  library_name = library_name.replace('.dylib','')
  if match:
    return FRAMEWORK_NAME_OVERRIDES.get(library_name, (library_name, 'A'))
  # Note: these styles are named after where I noticed them, not necessarily
  # where they originate. -RAF
  regexes = [r'([A-Za-z0-9_-]*)-([0-9\.]*)$', #apr style
             r'([A-Za-z0-9_-]*[a-zA-Z])\.([0-9\.]*)$', #gnu style
             r'([A-Za-z0-9_-]*[a-zA-Z])([0-9\.]*)$', #sqlite style
             ]
  for regex in regexes:
    match = re.match(regex, library_name)
    if match:
      name, version = match.groups()
      return FRAMEWORK_NAME_OVERRIDES.get(name, (name, version))

  # If we get here, we need a new regex. Throw an exception.
  raise ValueError('Library ' + library_path + ' with name ' + library_name +
                   ' did not match any known format, please update the'
                   ' script.')

if __name__ == '__main__':
  if len(sys.argv) < 3:
    print('Usage:', sys.argv[0], '/paths/to/libraries.dylib', 'output_dir')
    sys.exit(1)
  output_dir = sys.argv[-1]
  libs_to_convert = sys.argv[1:-1]
  libs_to_convert = recursively_discover_all_dependencies(libs_to_convert)
  libs_to_convert.sort()
  framework_names_and_versions = [lib_path_to_framework_and_version(l) for l 
                  in libs_to_convert]
  framework_names = [lib[0] for lib in framework_names_and_versions]
  framework_versions = [lib[1] for lib in framework_names_and_versions]
  
  framework_names_with_path = ['@executable_path/../Frameworks/' + l[0]
          + '.framework/Versions/' + l[1] +'/' + l[0] for l 
          in framework_names_and_versions]
  
  rlinks_fw_line = ('--rlinks_framework=[' + ' '.join(libs_to_convert)
            + ']:[' + ' '.join(framework_names_with_path) + ']')
  
  for lib,name,version in zip(libs_to_convert, framework_names, 
                framework_versions):
    #execute rtool (tool to build a bundle from the dylib) a crapton of times
    header_path = '/'.join(lib.split('/')[0:-1]) + '/include/' + name
    if version != '' and version != 'A':
      header_path += '-'+version
    try:
      header_path = ' '.join([header_path+'/'+h for h in 
                              os.listdir(header_path)])
    except OSError:
      # the directory didn't exist, we don't care.
      pass
    args = ['rtool',
            '--framework_root=@executable_path/../Frameworks',
            '--framework_name='+name,
            '--framework_version='+version,
            '--library='+lib,
            '--builddir='+output_dir,
            '--headers='+header_path,
            '--headers_no_root',
            rlinks_fw_line,
             ]
    status = os.spawnvp(os.P_WAIT, 'rtool', args)
    if status != 0:
      print('Something went wrong. rtool failed for', lib, 'with status', status)
      sys.exit(1)

  directories_to_visit = [output_dir+'/'+d for d in os.listdir(output_dir)
                          if d.endswith('.frwkproj')]
  for direct in directories_to_visit:
    frameworks = [direct+'/'+f for f in os.listdir(direct) if
                  f.endswith('.framework')]
    for f in frameworks:
      f_new = output_dir+'/'+f.split('/')[-1]
      try:
        shutil.rmtree(f_new)
      except Exception:
        pass
      shutil.move(f, f_new)
    shutil.rmtree(direct)
