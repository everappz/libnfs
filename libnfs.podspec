Pod::Spec.new do |s|
  s.name         = 'libnfs'
  s.version      = '16.2.0'
  s.summary      = 'NFS client library'
  s.description  = 'LIBNFS is a client library for accessing NFS shares over a network. '\
                   'It supports NFSv3 and NFSv4, provides both synchronous and asynchronous APIs, '\
                   'and implements MOUNT, NLM, NSM, portmap, and rquota protocols.'
  s.homepage     = 'https://github.com/everappz/libnfs'
  s.license      = { :type => 'LGPL-2.1+', :file => 'LICENCE-LGPL-2.1.txt' }
  s.author       = { 'Ronnie Sahlberg' => 'ronniesahlberg@gmail.com' }
  s.source       = { :git => 'https://github.com/everappz/libnfs.git', :tag => s.version.to_s }

  s.ios.deployment_target = '13.0'
  s.osx.deployment_target = '10.15'
  s.tvos.deployment_target = '13.0'

  s.preserve_paths = 'apple-config/**/*', 'cmake/**/*', 'COPYING', 'LICENCE-*.txt'
  s.libraries = 'c'
  s.requires_arc = false

  s.module_map = 'libnfs.modulemap'
  s.default_subspecs = 'Core'

  s.subspec 'Core' do |core|
    core.source_files =
      'apple-config/config.h',
      'include/**/*.h',
      'lib/*.{c,h}',
      'mount/*.{c,h}',
      'nfs/*.{c,h}',
      'nfs4/*.{c,h}',
      'nlm/*.{c,h}',
      'nsm/*.{c,h}',
      'portmap/*.{c,h}',
      'rquota/*.{c,h}'

    core.public_header_files =
      'include/nfsc/libnfs.h',
      'include/nfsc/libnfs-raw.h',
      'include/nfsc/libnfs-zdr.h',
      'mount/libnfs-raw-mount.h',
      'nfs/libnfs-raw-nfs.h',
      'nfs4/libnfs-raw-nfs4.h',
      'nlm/libnfs-raw-nlm.h',
      'nsm/libnfs-raw-nsm.h',
      'portmap/libnfs-raw-portmap.h',
      'rquota/libnfs-raw-rquota.h'

    core.private_header_files =
      'apple-config/config.h',
      'include/libnfs-private.h',
      'include/libnfs-multithreading.h',
      'include/slist.h',
      'lib/krb5-wrapper.h'

    core.exclude_files =
      'include/win32/**/*',
      'lib/libnfs-win32.def'

    core.header_dir = 'nfsc'

    core.compiler_flags = '-Wno-shorten-64-to-32'

    core.pod_target_xcconfig = {
      'HEADER_SEARCH_PATHS' => '"${PODS_TARGET_SRCROOT}/apple-config" "${PODS_TARGET_SRCROOT}/include" "${PODS_TARGET_SRCROOT}/include/nfsc" "${PODS_TARGET_SRCROOT}/lib" "${PODS_TARGET_SRCROOT}/mount" "${PODS_TARGET_SRCROOT}/nfs" "${PODS_TARGET_SRCROOT}/nfs4" "${PODS_TARGET_SRCROOT}/nlm" "${PODS_TARGET_SRCROOT}/nsm" "${PODS_TARGET_SRCROOT}/portmap" "${PODS_TARGET_SRCROOT}/rquota"',
      'GCC_PREPROCESSOR_DEFINITIONS' => 'HAVE_CONFIG_H=1 _U_=__attribute__((unused))',
    }

    # Create symlinks in include/nfsc/ for protocol headers so that
    # #include <nfsc/libnfs-raw-mount.h> etc. resolve via HEADER_SEARCH_PATHS.
    # Needed for CocoaPods framework mode where header_dir virtual mapping
    # doesn't apply during the pod's own compilation.
    core.script_phases = [{
      :name => 'Create nfsc header symlinks',
      :script => 'cd "${PODS_TARGET_SRCROOT}/include/nfsc" && ' \
                 '[ -L libnfs-raw-mount.h ]   || ln -s ../../mount/libnfs-raw-mount.h libnfs-raw-mount.h; ' \
                 '[ -L libnfs-raw-nfs.h ]     || ln -s ../../nfs/libnfs-raw-nfs.h libnfs-raw-nfs.h; ' \
                 '[ -L libnfs-raw-nfs4.h ]    || ln -s ../../nfs4/libnfs-raw-nfs4.h libnfs-raw-nfs4.h; ' \
                 '[ -L libnfs-raw-nlm.h ]     || ln -s ../../nlm/libnfs-raw-nlm.h libnfs-raw-nlm.h; ' \
                 '[ -L libnfs-raw-nsm.h ]     || ln -s ../../nsm/libnfs-raw-nsm.h libnfs-raw-nsm.h; ' \
                 '[ -L libnfs-raw-portmap.h ] || ln -s ../../portmap/libnfs-raw-portmap.h libnfs-raw-portmap.h; ' \
                 '[ -L libnfs-raw-rquota.h ]  || ln -s ../../rquota/libnfs-raw-rquota.h libnfs-raw-rquota.h; ' \
                 'true',
      :execution_position => :before_compile,
    }]
  end

  s.subspec 'ObjC' do |objc|
    objc.source_files = 'objc-wrapper/*.{h,m}'
    objc.public_header_files = 'objc-wrapper/NFSClient.h', 'objc-wrapper/NFSFileItem.h'
    objc.private_header_files = 'objc-wrapper/NFSContext.h'
    objc.dependency 'libnfs/Core'
    objc.requires_arc = true
  end
end
