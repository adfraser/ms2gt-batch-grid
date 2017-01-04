;+
  ; :Description:
  ;    When pointed toward a directory on an SSH server,
  ;    this routine will grid the MODIS .HDF files there
  ;    into the projection defined in the specified .gpd
  ;    file.
  ;    
  ;    Requires the files to be hosted on a remote ssh server
  ;    
  ;    Outputs gridded imagery to the remote server too.
  ; 
  ;    Acceptable input .hdf files are either MOD/MYD021KM (without the corresponding MOD03),
  ;                                           MOD/MYD02QKM (with the corresponding MOD03), or
  ;                                           MOD/MYD35_L2 
  ;                                           
  ;    Let's think about what kind of HDFs we could possibly have, and their ourputs:
  ;    MOD/MYD021KM -> Should be gridded into a ch31. Expect a dir full of MOD021KM files
  ;    MOD/MYD02QKM -> Should be gridded into a ch01soze, taking into account the associated MOD/MYD03. Expect a dir full of MOD02QKM and associated MOD03 files
  ;    MOD/MYD35_L2 -> Should be gridded into a cld0. Expect a dir full of MOD35_L2 files.
  ;                                           
  ; :Requires:
  ;    A working ms2gt installation (contact Terry Haran at NSIDC for latest version)                                          
  ;
  ; :Params:
  ;    username     The username to login to the server containing the .hdf files. [String]
  ;    servername   The name or IP address of the remote server hosting the files. [String]
  ;    hdffolder    The path to the hdf files on the remote server. [String]
  ;    outputfolder The path to put the output files on the remote server.  [String]
  ;    gridxsize    The x dimension of the grid specified in the .gpd file. [int or similar]
  ;    gridysize    The y dimension of the grid specified in the .gpd file. [int or similar] 
  ;    gpdfile      The name of the .gpd file.  [String]
  ;    
  ; :Example:
  ;    batcheverythinggrid_nectaraware, 'ubuntu', '144.6.238.206', '/limps_data/from_ftp_server/mod02_pluggaps', '/limps_data/nectar_outputs/griddedhdfs/2000', 4000, 4000, 'test.gpd'
  ;
  ; :Author: Alex Fraser, adfraser@utas.edu.au, ACE CRC, 2017
  ;
  ;-
pro batcheverythinggrid_nectaraware, username, servername, hdffolder, outputfolder, gridxsize, gridysize, gpdfile

  ;BASICALLY, GRID ALL HDFs IN THAT FOLDER INTO THEIR APPROPRIATE FORMAT.

  
  ;customise the runfiles based on the gpdfile name:
  openw, lun, 'runfile_1km', /get_lun
  printf, lun, 'mod02.pl . output listfile.txt '+gpdfile+' chanfile_1km.txt'
  free_lun, lun
  file_chmod, 'runfile_1km', /a_execute

  openw, lun, 'runfile_qkm', /get_lun
  printf, lun, 'mod02.pl . output listfile.txt '+gpdfile+' chanfile_qkm.txt ancilfile.txt 3 3'
  free_lun, lun
  file_chmod, 'runfile_qkm', /a_execute  
  
  openw, lun, 'runfile_cld', /get_lun
  printf, lun, 'mod35_l2.pl . output listfile.txt '+gpdfile+' chanfile_cld.txt'
  free_lun, lun
  file_chmod, 'runfile_cld', /a_execute

  ;add spacers to gridxsize and gridysize, form strings 5 digits long.
  if gridxsize gt 9999 then xpad=''
  if gridxsize le 9999 then xpad='0'
  if gridxsize le 999 then xpad='00'
  if gridxsize le 99 then xpad='000'
  if gridxsize le 9 then xpad='0000'
  if gridysize gt 9999 then ypad=''
  if gridysize le 9999 then ypad='0'
  if gridysize le 999 then ypad='00'
  if gridysize le 99 then ypad='000'
  if gridysize le 9 then ypad='0000'  
  gridxstring=xpad+strtrim(gridxsize,2)
  gridystring=ypad+strtrim(gridysize,2)

  
  spawn, "ssh "+username+"@"+servername+" 'find "+hdffolder+" -type f | grep hdf | sort '", hdflist

  ;find out what it is....
  samplefilename=file_basename(hdflist[0])
  goodbits=strmid(samplefilename, 3,3)  ;can be "021", "02Q", "03." or "35_"
  
  ;grid as a heap of ch31 mod02s.
  if goodbits eq '021' then begin
    
    for i=0, n_elements(hdflist)-1 do begin
      
      spawn, 'rsync -avP --timeout=5 '+username+'@'+servername+':'+hdflist[i]+' .', exit_status=rsyncreturn
      while rsyncreturn ne 0 do begin
        spawn, 'rsync -avP --timeout=10 '+username+'@'+servername+':'+hdflist[i]+' .', exit_status=rsyncreturn
      endwhile
      
      ;generate a new listfile
      openw, lun, 'listfile.txt', /get_lun
      printf, lun, file_basename(hdflist[i])
      free_lun, lun

      
      ;run the mod35_l2.pl runfile
      spawn, './runfile_1km'

      
      ;remove all hdfs
      spawn, 'rm -f *021KM*.hdf'


      if file_test('output_temm_ch31_'+gridxstring+'_'+gridystring+'.img') then begin

        ;get the good bits out of the baselist
        spawn, 'echo '+file_basename(hdflist[i])+' | cut -c 11-22', goodbits

        ;also get the first three chars (MOD/MYD)
        spawn, 'echo '+file_basename(hdflist[i])+' | cut -c 1-3', modmyd

        ;zip it
        spawn, 'gzip output_temm_ch31_'+gridxstring+'_'+gridystring+'.img'
        
        ;rename it
        spawn, 'mv output_temm_ch31_'+gridxstring+'_'+gridystring+'.img.gz '+modmyd+goodbits+'ch31.img.gz'
        
        
        ;copy it offsite
        spawn, 'rsync -rtvP --timeout=5 ./'+modmyd+goodbits+'ch31.img.gz '+username+'@'+servername+':'+outputfolder, exit_status=rsyncreturn
        while rsyncreturn ne 0 do begin
          spawn, 'rsync -rtvP --timeout=10 ./'+modmyd+goodbits+'ch31.img.gz '+username+'@'+servername+':'+outputfolder, exit_status=rsyncreturn
        endwhile
          
        ;rm it from here
        spawn, 'rm ./'+modmyd+goodbits+'ch31.img.gz'

        
      endif
        
    endfor
    
  endif
  
  
  ;grid as a heap of clouds.
  if goodbits eq '35_' then begin
    
    for i=0, n_elements(hdflist)-1 do begin

      spawn, 'rsync -rtvP --timeout=5 '+username+'@'+servername+':'+hdflist[i]+' .', exit_status=rsyncreturn
      while rsyncreturn ne 0 do begin
        spawn, 'rsync -rtvP --timeout=10 '+username+'@'+servername+':'+hdflist[i]+' .', exit_status=rsyncreturn
      endwhile

      ;generate a new listfile
      openw, lun, 'listfile.txt', /get_lun
      printf, lun, file_basename(hdflist[i])
      free_lun, lun

      ;run the mod35_l2.pl runfile
      spawn, './runfile_cld'

      ;remove all hdfs
      spawn, 'rm -f *35_L2*.hdf'


      if file_test('output_rawm_cld0_'+gridxstring+'_'+gridystring+'.img') then begin

        ;get the good bits out of the baselist
        spawn, 'echo '+file_basename(hdflist[i])+' | cut -c 11-22', goodbits

        ;also get the first three chars (MOD/MYD)
        spawn, 'echo '+file_basename(hdflist[i])+' | cut -c 1-3', modmyd

        ;zip it
        spawn, 'gzip output_rawm_cld0_'+gridxstring+'_'+gridystring+'.img'

        ;rename it
        spawn, 'mv output_rawm_cld0_'+gridxstring+'_'+gridystring+'.img.gz '+modmyd+'35_L2.A'+goodbits+'.img.gz'

        ;copy it offsite
        spawn, 'rsync -rtvP --timeout=5 ./'+modmyd+'35_L2.A'+goodbits+'.img.gz '+username+'@'+servername+':'+outputfolder, exit_status=rsyncreturn
        while rsyncreturn ne 0 do begin
          spawn, 'rsync -rtvP --timeout=10 ./'+modmyd+'35_L2.A'+goodbits+'.img.gz '+username+'@'+servername+':'+outputfolder, exit_status=rsyncreturn
        endwhile
        
        ;rm it from here
        spawn, 'rm ./'+modmyd+'35_L2.A'+goodbits+'.img.gz'

        
      endif

    endfor    
    
    
  endif
  
  
  ;grid them as a qkm and mod03 pair.
  if (goodbits eq '02Q') or (goodbits eq '03.') then begin
    ;need to split the search up into 02qs and 03.s.
    spawn, "ssh "+username+"@"+servername+" 'find "+hdffolder+" -type f | grep 02Q | grep hdf | sort '", qkmlist
    spawn, "ssh "+username+"@"+servername+" 'find "+hdffolder+" -type f | grep D03. | grep hdf | sort '", geolist

    if n_elements(qkmlist) ne n_elements(geolist) then stop
    
    spawn, 'rsync -avP --timeout=5 '+username+'@'+servername+':'+qkmlist[i]+' .', exit_status=rsyncreturn
    while rsyncreturn ne 0 do begin
      spawn, 'rsync -avP --timeout=10 '+username+'@'+servername+':'+qkmlist[i]+' .', exit_status=rsyncreturn
    endwhile
    spawn, 'rsync -avP --timeout=5 '+username+'@'+servername+':'+geolist[i]+' .', exit_status=rsyncreturn
    while rsyncreturn ne 0 do begin
      spawn, 'rsync -avP --timeout=10 '+username+'@'+servername+':'+geolist[i]+' .', exit_status=rsyncreturn
    endwhile    
    
    ;generate a new listfile
    openw, lun, 'listfile.txt', /get_lun
    printf, lun, file_basename(qkmlist[i])
    free_lun, lun

    ;run the mod35_l2.pl runfile
    spawn, './runfile_qkm'

    ;remove all hdfs
    spawn, 'rm -f *02QKM*.hdf'    
    
    
    if file_test('output_refm_ch01_'+gridxstring+'_'+gridystring+'.img') then begin

      ;get the good bits out of the baselist
      spawn, 'echo '+file_basename(qkmlist[i])+' | cut -c 11-22', goodbits

      ;also get the first three chars (MOD/MYD)
      spawn, 'echo '+file_basename(qkmlist[i])+' | cut -c 1-3', modmyd
      
      ref=fltarr(gridxsize,gridysize)
      soze=fltarr(gridxsize,gridysize)

      ;open our new outputs, and perform the soze correction in place.
      openr, lun, 'output_refm_ch01_'+gridxstring+'_'+gridystring+'.img', /get_lun
      readu, lun, ref
      free_lun, lun
      openr, lun, 'output_scaa_soze_'+gridxstring+'_'+gridystring+'.img', /get_lun
      readu, lun, soze
      free_lun, lun
      ;rm the ref and soze files
      spawn, 'rm -f *refm*.img'
      spawn, 'rm -r *scaa*.img'
      
      outputdata=ref/cos(soze*!DTOR)
      outputdata[where(soze ge 86)]=-9999.
      
      openw, lun, modmyd+goodbits+'ch01_soze_corrected.img', /get_lun
      writeu, lun, outputdata
      free_lun, lun
      
      ;zip it
      spawn, 'gzip '+modmyd+goodbits+'ch01_soze_corrected.img'
      
      ;copy it back to whence it came!
      spawn, 'rsync -rtvP --timeout=5 ./'+modmyd+goodbits+'ch01_soze_corrected.img.gz '+username+'@'+servername+':'+outputfolder, exit_status=rsyncreturn
      while rsyncreturn ne 0 do begin
        spawn, 'rsync -rtvP --timeout=10 ./'+modmyd+goodbits+'ch01_soze_corrected.img.gz '+username+'@'+servername+':'+outputfolder, exit_status=rsyncreturn
      endwhile

      ;rm it from here
      spawn, 'rm ./'+modmyd+goodbits+'ch01_soze_corrected.img.gz'


    endif
    
  endif
  
  
  
  
  
  
  
  
  stop
  



end