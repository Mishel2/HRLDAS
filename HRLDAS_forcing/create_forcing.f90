










program create_forcing
  use module_grib
  use module_geo_em
  use kwm_grid_utilities
  use kwm_date_utilities
  use kwm_string_utilities
  implicit none

  character(len=9), parameter :: version = "v20150518"

  character(len=256) :: namelist_file
  character(len=13) :: date

  type (geo_em_type) :: geo_em


  integer, parameter :: MAXTEMPLATE = 10      

  type DataBuffer
     character(len=256)                         :: label
     character(len=256)                         :: units
     real, pointer,      dimension(:,:)         :: field
     character(len=19)                          :: hdate ! A punctuated date, out to seconds.
     character(len=256), dimension(MAXTEMPLATE) :: flnm_template
     real                                       :: layer1
     real                                       :: layer2
     character(len=4)                           :: remap_type
     integer                                    :: fatality ! How we may or may not handle missing data.
  end type DataBuffer

  type VtableEntry
     integer :: g1_parm
     integer :: g1_levtyp
     integer :: level1
     integer :: level2
     character(len=32) :: name
     character(len=32) :: units
     character(len=32) :: desc
     integer :: g2_discp
     integer :: g2_cat
     integer :: g2_parm
     integer :: g2_levtyp
  end type VtableEntry

  type(VtableEntry), dimension(64) :: vtable
  integer :: vtable_count

  type (DataBuffer) ::    Tprev,    Tcurrent,    Tpost
  type (DataBuffer) ::    Qprev,    Qcurrent,    Qpost
  type (DataBuffer) ::    Pprev,    Pcurrent,    Ppost
  type (DataBuffer) ::    Uprev,    Ucurrent,    Upost
  type (DataBuffer) ::    Vprev,    Vcurrent,    Vpost
  type (DataBuffer) ::   LWprev,   LWcurrent,   LWpost
  type (DataBuffer) ::  SW1prev,  SW1current,  SW1post
  type (DataBuffer) ::  SW2prev,  SW2current,  SW2post
  type (DataBuffer) :: PCP1prev, PCP1current, PCP1post
  type (DataBuffer) :: PCP2prev, PCP2current, PCP2post
  type (DataBuffer) ::    Hprev,    Hcurrent,    Hpost

  type (DataBuffer) :: WEASDprev, WEASDcurrent, WEASDpost
  type (DataBuffer) :: CANWTprev, CANWTcurrent, CANWTpost
  type (DataBuffer) ::   SKTprev,   SKTcurrent,   SKTpost
  type (DataBuffer), dimension(4) :: STprev, STcurrent, STpost
  type (DataBuffer), dimension(4) :: SMprev, SMcurrent, SMpost

  type (DataBuffer) :: Zcurrent
  type (DataBuffer) :: LANDSEA
  type (DataBuffer) :: gvfmin
  type (DataBuffer) :: gvfmax
  type (DataBuffer) :: vegfra
  type (DataBuffer) :: lai

  integer, pointer, dimension(:,:)   :: tempint    ! temporary array
  
  real , dimension(4) :: dzs, zs

  integer :: i, j
  integer :: ierr
  character(len=1) :: hgrid
  character(len=8) :: name

  integer :: ncid
  integer :: ihour
  integer :: numarg
  integer :: unmatched


  ! Namelist variables
  character(len=13)  :: startdate ! A punctuated date out to hours
  character(len=13)  :: enddate   ! A punctuated date out to hours
  character(len=256) :: DataDir
  character(len=256) :: OutputDir
  character(len=256) :: geo_em_flnm
  character(len=256) :: initial_flnm
  integer            :: rainfall_interp ! 0=Nearest Neighbor; 1=more expensive, grid fill method
  integer            :: full_ic_frq     ! How frequently (hours) to make full surface initial conditions.
                                        ! FULL_IC_FRC==0 means do this only at the startdate.
                                        ! FULL_IC_FRC==-1 means never make full surface initial conditions.
  logical            :: rescale_shortwave
  logical            :: update_snow
  logical            :: forcing_height_2d
  logical            :: truncate_sw
  integer            :: expand_loop
  logical            :: init_lai
  logical            :: vary_lai
  logical            :: mask_water
  character(len=256), dimension(MAXTEMPLATE) :: Tfile_template         ! T forcing
  character(len=256), dimension(MAXTEMPLATE) :: Qfile_template         ! Q forcing
  character(len=256), dimension(MAXTEMPLATE) :: Pfile_template         ! P forcing
  character(len=256), dimension(MAXTEMPLATE) :: Ufile_template         ! U forcing
  character(len=256), dimension(MAXTEMPLATE) :: Vfile_template         ! V forcing
  character(len=256), dimension(MAXTEMPLATE) :: LWfile_template        ! LW forcing
  character(len=256), dimension(MAXTEMPLATE) :: SWfile_primary         ! SW forcing
  character(len=256), dimension(MAXTEMPLATE) :: SWfile_secondary       ! Optional SW forcing
  character(len=256), dimension(MAXTEMPLATE) :: PCPfile_primary        ! Precipitation forcing
  character(len=256), dimension(MAXTEMPLATE) :: PCPfile_secondary      ! Optional precipitation forcing
  character(len=256), dimension(MAXTEMPLATE) :: Hfile_template         ! Optional 2D forcing height

  character(len=256), dimension(MAXTEMPLATE) :: WEASDfile_template     ! SWE initial field
  character(len=256), dimension(MAXTEMPLATE) :: CANWTfile_template     ! Canopy water initial field
  character(len=256), dimension(MAXTEMPLATE) :: SKINTfile_template     ! Skin temperature initial
  character(len=256), dimension(4,MAXTEMPLATE) :: STfile_template      ! Soil temperature initial
  character(len=256), dimension(4,MAXTEMPLATE) :: SMfile_template      ! Soil moisture initial

  character(len=256), dimension(MAXTEMPLATE) :: Zfile_template         ! source model surface elevation
  character(len=256), dimension(MAXTEMPLATE) :: LANDSfile_template     ! Land-sea mask from forcing



  namelist /files/ startdate, enddate, DataDir, OutputDir, & 
       geo_em_flnm,                                        &
       rainfall_interp, full_ic_frq, rescale_shortwave,    &
       update_snow, forcing_height_2d,                     &
       truncate_sw, expand_loop,                           &
       init_lai, vary_lai,mask_water,                      &
       Tfile_template, Qfile_template, Pfile_template,     &
       Ufile_template, Vfile_template, LWfile_template,    &
       SWfile_primary, SWfile_secondary, PCPfile_primary,  &
       PCPfile_secondary, Hfile_template, WEASDfile_template,&
       CANWTfile_template, SKINTfile_template, STfile_template, &
       SMfile_template, Zfile_template, LANDSfile_template
       

  full_ic_frq        = 0
  rainfall_interp    = 1
  rescale_shortwave  = .FALSE.
  update_snow        = .FALSE.
  forcing_height_2d  = .FALSE.
  truncate_sw        = .FALSE.
  init_lai           = .FALSE.
  vary_lai           = .FALSE.
  mask_water         = .FALSE.
  expand_loop        = 0
  Tfile_template     = " "
  Qfile_template     = " "
  Pfile_template     = " "
  Ufile_template     = " "
  Vfile_template     = " "
  LWfile_template    = " "
  SWfile_primary     = " "
  SWfile_secondary   = " "
  PCPfile_primary    = " "
  PCPfile_secondary  = " "
  Hfile_template     = " "
  WEASDfile_template = " "
  CANWTfile_template = " "
  SKINTfile_template = " "
  STfile_template    = " "
  SMfile_template    = " "
  Zfile_template     = " "
  LANDSfile_template = " "


!--------------------------------------------------------------------------
! Read namelist
!--------------------------------------------------------------------------

  numarg = iargc()
  if (numarg > 0) then
     call getarg(1, namelist_file)
  else
     namelist_file = "namelist.input"
  endif

  open(12,file=trim(namelist_file), form='formatted', action='read', status='old', iostat=ierr)
  if (ierr /= 0) then
     write(*,*)
     write(*,'("  *****  Failure trying to open file ''", A, "''")') trim(namelist_file)
     write(*,*)
     write(*,'("Program takes an optional command-line argument, the name of the namelist file.")')
     if ( numarg > 0 ) then
        write(*,'("In this case, you provided the name ''", A, "''")') trim(namelist_file)
     endif
     write(*,*)
     write(*,'("With no command-line argument, program expects the namelist file to be")')
     write(*,'("called ''namelist.input'', which must be present in the working directory. ")')
     write(*,*)
     stop
  endif
  read(12,files) 
  close(12)

!--------------------------------------------------------------------------
! Read Vtable
!--------------------------------------------------------------------------

  call read_vtable(trim(namelist_file))   ! subroutine below

!--------------------------------------------------------------------------
! Begin to fill in our file name template strings
!--------------------------------------------------------------------------

  do j = 1, maxtemplate
     call strrep(    Tfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(    Qfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(    Pfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(    Ufile_template(j), "<DataDir>", trim(DataDir))
     call strrep(    Vfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(   LWfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(    SWfile_primary(j), "<DataDir>", trim(DataDir))
     call strrep(  SWfile_secondary(j), "<DataDir>", trim(DataDir))
     call strrep(   PCPfile_primary(j), "<DataDir>", trim(DataDir))
     call strrep( PCPfile_secondary(j), "<DataDir>", trim(DataDir))
     call strrep(    Hfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(WEASDfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(CANWTfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(SKINTfile_template(j), "<DataDir>", trim(DataDir))
     do i = 1, 4
        call strrep(STfile_template(i,j), "<DataDir>", trim(DataDir))
        call strrep(SMfile_template(i,j), "<DataDir>", trim(DataDir))
     enddo
     call strrep(    Zfile_template(j), "<DataDir>", trim(DataDir))
     call strrep(LANDSfile_template(j), "<DataDir>", trim(DataDir))
  enddo

!------------------------------------------------------------------------
! Read the geo_em file
!------------------------------------------------------------------------

  call strrep(geo_em_flnm, "<DataDir>", trim(DataDir))
  write(*,'(A)') 'geo_em_flnm    = "'//trim(geo_em_flnm)//'"'

  call read_geo_em_file(trim(geo_em_flnm), geo_em, ierr)
  if (ierr /= 0) stop "Problem reading geo_em file"
  write(hgrid,'(I1)') geo_em%grid_id

  nullify(gvfmin%field)
  nullify(gvfmax%field)
  nullify(vegfra%field)
  allocate(gvfmin%field(geo_em%idim, geo_em%jdim))
  allocate(gvfmax%field(geo_em%idim, geo_em%jdim))
  allocate(vegfra%field(geo_em%idim, geo_em%jdim))
  if(vary_lai .or. init_lai) allocate(lai%field(geo_em%idim, geo_em%jdim))

  gvfmin%field(:,:) = minval(geo_em%veg,3)
  gvfmax%field(:,:) = maxval(geo_em%veg,3)

! Not certain why the following is necessary since we are simulating over the WRF points
!    so they should have been filled properly already, commenting (Barlage 20140529)

!  call fillsm(gvfmin%field, (geo_em%use /= geo_em%iswater), geo_em%idim, geo_em%jdim)
!  call fillsm(gvfmax%field, (geo_em%use /= geo_em%iswater), geo_em%idim, geo_em%jdim)

  where (gvfmin%field < 0.0) gvfmin%field = 0.0
  where (gvfmax%field < 0.0) gvfmax%field = 0.0

!--------------------------------------------------------------------------
! Data buffer structure initializations
!--------------------------------------------------------------------------

  call data_buffer_init(    Tprev,    Tcurrent,    Tpost,     Tfile_template,"bint", "T2D"                )
  call data_buffer_init(    Qprev,    Qcurrent,    Qpost,     Qfile_template,"bint", "Q2D"                )
  call data_buffer_init(    Pprev,    Pcurrent,    Ppost,     Pfile_template,"bint", "PSFC"               )
  call data_buffer_init(    Uprev,    Ucurrent,    Upost,     Ufile_template,"bint", "U2D"                )
  call data_buffer_init(    Vprev,    Vcurrent,    Vpost,     Vfile_template,"bint", "V2D"                )
  call data_buffer_init(   LWprev,   LWcurrent,   LWpost,    LWfile_template,"bint", "LWDOWN"             )
  call data_buffer_init(  SW1prev,  SW1current,  SW1post,     SWfile_primary,"bint", "SWDOWN"  ,fatality=2)
  call data_buffer_init(  SW2prev,  SW2current,  SW2post,   SWfile_secondary,"bint", "SWDOWN"             )
  call data_buffer_init( PCP1prev, PCP1current, PCP1post,    PCPfile_primary, "4pt", "RAINRATE",fatality=2)
  call data_buffer_init( PCP2prev, PCP2current, PCP2post,  PCPfile_secondary, "4pt", "RAINRATE"           )
  call data_buffer_init(    Hprev,    Hcurrent,    Hpost,     Hfile_template,"bint", "ZLVL2D"             )
  call data_buffer_init(WEASDprev,WEASDcurrent,WEASDpost, WEASDfile_template,"16pt", "SNOW"               )
  call data_buffer_init(CANWTprev,CANWTcurrent,CANWTpost, CANWTfile_template,"16pt", "CANWAT"             )
  call data_buffer_init(  SKTprev,  SKTcurrent,  SKTpost, SKINTfile_template,"bint", "TSK"                )
  do i = 1, 4
     write(name, '("STEMP_",i1)') i
     call data_buffer_init(  STprev(i),   STcurrent(i),   STpost(i), STfile_template(i,:),  "16pt", name )
     write(name, '("SMOIS_",i1)') i
     call data_buffer_init(  SMprev(i),   SMcurrent(i),   SMpost(i), SMfile_template(i,:),  "16pt", name )
  enddo

  Zcurrent%label    = "TERRAIN"
  Zcurrent%hdate    = "0000-00-00_00:00:00"
  Zcurrent%flnm_template = Zfile_template

  LANDSEA%label         = "LANDSEA"
  LANDSEA%hdate         = "0000-00-00_00:00:00"
  LANDSEA%flnm_template = LANDSfile_template

  gvfmin%label = "SHDMIN"
  gvfmin%units = "%"
  gvfmin%layer1 = -1.E36
  gvfmin%layer2 = -1.E36

  gvfmax%label = "SHDMAX"
  gvfmax%units = "%"
  gvfmax%layer1 = -1.E36
  gvfmax%layer2 = -1.E36

  vegfra%label = "VEGFRA"
  vegfra%units = "%"
  vegfra%layer1 = -1.E36
  vegfra%layer2 = -1.E36

  if(vary_lai .or. init_lai) then
    lai%label = "LAI"
    lai%units = "m^2/m^2"
    lai%layer1 = -1.E36
    lai%layer2 = -1.E36
  end if

!--------------------------------------------------------------------------
! Loop DATELOOP is the main loop over time.
!--------------------------------------------------------------------------

  date = startdate

  DATELOOP : do while ( date <= enddate )

     call geth_idts(date(1:13), startdate(1:13), ihour)

     print*, 'Date = ', Date, "  ihour = ", ihour

     call interpolate_vegetation("VEGFRA", date, geo_em%idim, geo_em%jdim, geo_em%veg, vegfra%field)

     if(vary_lai) call interpolate_vegetation("LAI", date, geo_em%idim, geo_em%jdim, geo_em%lai, lai%field)

! Not certain why the following is necessary since we are simulating over the WRF points
!    so they should have been filled properly already, commenting (Barlage 20140529)
!     call fillsm(vegfra%field, (geo_em%use /= geo_em%iswater), geo_em%idim, geo_em%jdim)

     call process(date, Tcurrent, Tprev, Tpost, geo_em, expand_loop)
     call process(date, Qcurrent, Qprev, Qpost, geo_em, expand_loop)
     call process(date, Pcurrent, Pprev, Ppost, geo_em, expand_loop)
     call process(date, Ucurrent, Uprev, Upost, geo_em, expand_loop)
     call process(date, Vcurrent, Vprev, Vpost, geo_em, expand_loop)
     call process(date, LWcurrent,   LWprev,   LWpost, geo_em, expand_loop)
     call process(date, SW1current,  SW1prev,  SW1post, geo_em, expand_loop)
     call process(date, SW2current,  SW2prev,  SW2post, geo_em, expand_loop)
     call process(date, PCP1current, PCP1prev, PCP1post, geo_em, expand_loop)
     call process(date, PCP2current, PCP2prev, PCP2post, geo_em, expand_loop)
     if(forcing_height_2d) call process(date, Hcurrent, Hprev, Hpost, geo_em, expand_loop)
     
     call open_netcdf_for_output( &
          trim(OutputDir)//date(1:4)//date(6:7)//date(9:10)//date(12:13)//".LDASIN_DOMAIN"//hgrid, &
          ncid, version, geo_em%idim, geo_em%jdim, geo_em, .false.)

     ! For output, the Tcurrent%field needs to be readjusted to model elevation
     Tcurrent%field = Tcurrent%field + ( -0.0065 * geo_em%ter )

     ! Fill in missing areas in PCP1 with data from PCP2
     where (PCP2current%field <=0) PCP2current%field=0
     where (PCP1current%field <-1.E25) PCP1current%field=PCP2current%field
     where (PCP1current%field <=0) PCP1current%field=0

     ! Fill in missing areas in SW1 with data from SW2
     where (SW2current%field <= 0) SW2current%field = 0
     where (SW1current%field <= 0) SW1current%field = SW2current%field
     where (SW1current%field <= 0) SW1current%field = 0

     ! If the sun isn't up, there shouldn't be any SW.
     ! This may be a little extreme (ignores atmospheric refraction effects, e.g.); it 
     ! causes an awfully abrupt terminator.  Will have to consider.
     
     if (truncate_sw) &
       call nighttime_SW(SW1current%hdate, SW1current%field, geo_em%idim, geo_em%jdim, geo_em)

     if (mask_water) then
       where(geo_em%use == geo_em%iswater)    Tcurrent%field = -1.e36
       where(geo_em%use == geo_em%iswater)    Qcurrent%field = -1.e36
       where(geo_em%use == geo_em%iswater)    Pcurrent%field = -1.e36
       where(geo_em%use == geo_em%iswater)    Ucurrent%field = -1.e36
       where(geo_em%use == geo_em%iswater)    Vcurrent%field = -1.e36
       where(geo_em%use == geo_em%iswater)   LWcurrent%field = -1.e36
       where(geo_em%use == geo_em%iswater)  SW1current%field = -1.e36
       where(geo_em%use == geo_em%iswater) PCP1current%field = -1.e36
       if(forcing_height_2d) where(geo_em%use == geo_em%iswater) Hcurrent%field = -1.e36
     end if

     if(date == startdate) then  ! Do a quick test to see if any valid land points have problems
       unmatched = count(Tcurrent%field < -1.e30 .and. geo_em%use /= geo_em%iswater)
       if(unmatched > 0) then
         print *, "You have this many undefined T points over valid land points: ", unmatched
         print *, "This tends to happen around coastlines or for unresolved islands in your forcing data"
      	 print *, "===== Consider increasing expand_loop in namelist ====="
      	 print *, "However, this may also occur if your forcing source does not cover your domain."
      	 stop
       end if
     end if
     
     call output_databuffer(ncid,    Tcurrent)
     call output_databuffer(ncid,    Qcurrent)
     call output_databuffer(ncid,    Pcurrent)
     call output_databuffer(ncid,    Ucurrent)
     call output_databuffer(ncid,    Vcurrent)
     call output_databuffer(ncid,   LWcurrent)
     call output_databuffer(ncid,  SW1current)
     call output_databuffer(ncid, PCP1current)
     if(forcing_height_2d) call output_databuffer(ncid,    Hcurrent)

     if (date(12:13) == "00" .and. update_snow) then
        where (WEASDcurrent%field < 0)       WEASDcurrent%field = 0.0
        where (geo_em%use == geo_em%iswater) WEASDcurrent%field = 0.0
        call output_databuffer(ncid, WEASDcurrent)
     endif

     if (date(12:13) == "00") then
        where (geo_em%use == geo_em%iswater) vegfra%field = 0.0
        call output_databuffer(ncid, vegfra)
     endif

     if (date(12:13) == "00" .and. vary_lai) then
        where (geo_em%use == geo_em%iswater) lai%field = 0.0
        call output_databuffer(ncid, lai)
     endif

     ierr = nf90_close(ncid)
     call error_handler(ierr, "Problem closing Netcdf file")

     if ( full_ic_frq > -1 ) then  ! full_ic_frq == -1 turns off extra processing for initial conditions.
        if ( ( (full_ic_frq>0) .and. (mod(ihour, full_ic_frq)==0) ) .or. ( ihour==0 ) ) then

           call open_netcdf_for_output( trim(OutputDir)//"HRLDAS_setup_"//date(1:4)//date(6:7)//date(9:10)//date(12:13)//"_d"//hgrid, &
             ncid, version, geo_em%idim, geo_em%jdim, geo_em, .true.)

           call output_timestring_to_netcdf(ncid, date)
	   
	   where(geo_em%use .eq. geo_em%iswater) geo_em%tmn = -1.e36

           call output_to_netcdf(ncid,     "XLAT", "degree_north", geo_em%lat, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,    "XLONG", "degree_east" , geo_em%lon, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,      "TMN",           "K" , geo_em%tmn, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,      "HGT",           "m" , geo_em%ter, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,   "SEAICE",            "" , geo_em%ice, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,"MAPFAC_MX",            "" , geo_em%mmx, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,"MAPFAC_MY",            "" , geo_em%mmy, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,   "SHDMAX",           "%" , gvfmax%field, geo_em%idim, geo_em%jdim)
           call output_to_netcdf(ncid,   "SHDMIN",           "%" , gvfmin%field, geo_em%idim, geo_em%jdim)

           if(init_lai) then
	     call interpolate_vegetation("LAI", date, geo_em%idim, geo_em%jdim, geo_em%lai, lai%field)
             call output_to_netcdf(ncid,   "LAI",      "m^2/m^2" , lai%field, geo_em%idim, geo_em%jdim)
	   end if

           allocate(tempint(geo_em%idim, geo_em%jdim))
	   tempint = int(geo_em%msk)
           call output_to_netcdf_int(ncid, "XLAND",           "" , tempint, geo_em%idim, geo_em%jdim)
	   tempint = int(geo_em%use)
           call output_to_netcdf_int(ncid,"IVGTYP",           "" , tempint, geo_em%idim, geo_em%jdim)
	   tempint = int(geo_em%soi)
           call output_to_netcdf_int(ncid,"ISLTYP",           "" , tempint, geo_em%idim, geo_em%jdim)


           call process(date, WEASDcurrent, WEASDprev, WEASDpost, geo_em, expand_loop);
           where (WEASDcurrent%field < 0) WEASDcurrent%field = 0
           call output_databuffer(ncid, WEASDcurrent)

           call process(date, CANWTcurrent, CANWTprev, CANWTpost, geo_em, expand_loop);
           where (CANWTcurrent%field < 0) CANWTcurrent%field = 0
           call output_databuffer(ncid, CANWTcurrent)
           deallocate(CANWTprev%field, stat=ierr)
           deallocate(CANWTcurrent%field, stat=ierr)
           deallocate(CANWTpost%field, stat=ierr)

           call process(date, SKTcurrent, SKTprev, SKTpost, geo_em, expand_loop);
           call output_databuffer(ncid,   SKTcurrent)
           deallocate(SKTprev%field, stat=ierr)
           deallocate(SKTcurrent%field, stat=ierr)
           deallocate(SKTpost%field, stat=ierr)

           do i = 1, 4
              call process(date, STcurrent(i), STprev(i), STpost(i), geo_em, expand_loop);
              call process(date, SMcurrent(i), SMprev(i), SMpost(i), geo_em, expand_loop);
	      dzs(i) = SMcurrent(i)%layer2 - SMcurrent(i)%layer1
	      if (i == 1) then
	        zs(i) = 0.5 * SMcurrent(i)%layer2
	      else
	        zs(i) = 0.5*dzs(i) + sum(dzs(1:i-1))
	      end if
           enddo

           call output_to_netcdf_vector(ncid, "DZS", "m", 4, dzs)
           call output_to_netcdf_vector(ncid, "ZS", "m", 4, zs)

           unmatched = count(STcurrent(1)%field < -1.e30 .and. geo_em%use /= geo_em%iswater)
           if(unmatched > 0) then
             print *, "You have this many undefined soil points over valid land points: ", unmatched
             print *, "This tends to happen around coastlines or for unresolved islands in your forcing data"
      	     print *, "===== Consider increasing expand_loop in namelist ====="
      	     print *, "However, this may also occur if your forcing source does not cover your domain."
      	     stop
           end if

           call output_to_netcdf_soil(ncid, "TSLB", "K", STcurrent(1)%field, STcurrent(2)%field, STcurrent(3)%field,  &
	                                STcurrent(4)%field, geo_em%idim, geo_em%jdim, 4)
           do i = 1, 4
              deallocate(STprev(i)%field, stat=ierr)
              deallocate(STcurrent(i)%field, stat=ierr)
              deallocate(STpost(i)%field, stat=ierr)
           enddo

           do i = 1, 4
              ! Put a rough maximum on soil moisture, before we write it out.
              where (SMcurrent(i)%field > 0.5) SMcurrent(i)%field = 0.5  ! Change to 0.5 (Barlage 20140529)
           enddo

           call output_to_netcdf_soil(ncid, "SMOIS", "m^3/m^3", SMcurrent(1)%field, SMcurrent(2)%field, SMcurrent(3)%field,  &
	                                SMcurrent(4)%field, geo_em%idim, geo_em%jdim, 4)
           do i = 1, 4
              deallocate(SMprev(i)%field, stat=ierr)
              deallocate(SMcurrent(i)%field, stat=ierr)
              deallocate(SMpost(i)%field, stat=ierr)
           enddo

           ierr = nf90_close(ncid)
           call error_handler(ierr, "Problem closing initial file")

        endif
     endif

     call geth_newdate(date, date, 1)
  enddo DATELOOP


  deallocate(Tprev%field, stat=ierr)
  deallocate(Tcurrent%field, stat=ierr)
  deallocate(Tpost%field, stat=ierr)

  deallocate(Qprev%field, stat=ierr)
  deallocate(Qcurrent%field, stat=ierr)
  deallocate(Qpost%field, stat=ierr)

  deallocate(Pprev%field, stat=ierr)
  deallocate(Pcurrent%field, stat=ierr)
  deallocate(Ppost%field, stat=ierr)

  deallocate(Uprev%field, stat=ierr)
  deallocate(Ucurrent%field, stat=ierr)
  deallocate(Upost%field, stat=ierr)

  deallocate(Vprev%field, stat=ierr)
  deallocate(Vcurrent%field, stat=ierr)
  deallocate(Vpost%field, stat=ierr)

  deallocate(LWprev%field, stat=ierr)
  deallocate(LWcurrent%field, stat=ierr)
  deallocate(LWpost%field, stat=ierr)

  deallocate(SW1prev%field, stat=ierr)
  deallocate(SW1current%field, stat=ierr)
  deallocate(SW1post%field, stat=ierr)

  deallocate(SW2prev%field, stat=ierr)
  deallocate(SW2current%field, stat=ierr)
  deallocate(SW2post%field, stat=ierr)

  deallocate(PCP1prev%field, stat=ierr)
  deallocate(PCP1current%field, stat=ierr)
  deallocate(PCP1post%field, stat=ierr)

  deallocate(PCP2prev%field, stat=ierr)
  deallocate(PCP2current%field, stat=ierr)
  deallocate(PCP2post%field, stat=ierr)

  deallocate(Hprev%field, stat=ierr)
  deallocate(Hcurrent%field, stat=ierr)
  deallocate(Hpost%field, stat=ierr)

  deallocate(WEASDprev%field, stat=ierr)
  deallocate(WEASDcurrent%field, stat=ierr)
  deallocate(WEASDpost%field, stat=ierr)

  deallocate(LANDSEA%field, stat=ierr)
  deallocate(zcurrent%field, stat=ierr)
  deallocate(gvfmin%field, stat=ierr)
  deallocate(gvfmax%field, stat=ierr)
  deallocate(vegfra%field, stat=ierr)
  deallocate(geo_em%lat, stat=ierr)
  deallocate(geo_em%lon, stat=ierr)
  deallocate(geo_em%ter, stat=ierr)
  deallocate(geo_em%use, stat=ierr)
  deallocate(geo_em%veg, stat=ierr)
  
  call grib2_clear_parameter_table


contains

!==============================================================================
!==============================================================================
  subroutine read_vtable(filename)
    implicit none
    character(len=*), intent(in) :: filename

    character(len=256) :: string
    integer :: ierr
    integer :: jstart, jbar
    character(len=64) :: val
    integer :: vcount

    ! 
    ! Open the file
    !
    open(12, file=filename, status='old', form='formatted', iostat=ierr)

    !
    ! Scan forward until we find the string <VTABLE>
    !
    do
       read(12, '(A255)', iostat=ierr) string
       if (ierr /= 0) stop "Problem searching for <VTABLE>"
       if (string == "<VTABLE>") exit
    enddo

    !
    ! We've found the <VTABLE> marker.  Now read the table information
    !

    vcount = 0
    VLOOP : do
       read(12, '(A255)', iostat=ierr) string
       if (ierr /= 0) stop "Problem reading Variable Table"
       if (string == "</VTABLE>") exit
       if (string(1:1) == "-") cycle
       if (string(1:1) == "#") cycle
       if (string(1:5) == "GRIB1") cycle
       if (string(1:5) == "Param") cycle
       write(*, '(A)') trim(string)

       jstart = 1
       vcount = vcount + 1
       if (vcount > size(vtable)) then
          write(*,'(/," ***** ERROR *****")')
          write(*,'(" *****       Parameterized size of vtable (",I4,") is too small.")') size(vtable)
          write(*,'(" *****       Change the dimensions of vtable and recompile.",/)')
          stop
       endif

       BLOOP : do j = 1, 11
          ! The fields are delimited by '|'
          jbar = index(string(jstart:255),'|') + jstart - 2
          val = trim(adjustl(string(jstart:jbar)))
          jstart = jbar + 2
          select case (j)
          case (1)
             read(val,*,iostat=ierr) vtable(vcount)%g1_parm
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          case (2)
             read(val,*,iostat=ierr) vtable(vcount)%g1_levtyp
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          case (3)
             read(val,*,iostat=ierr) vtable(vcount)%level1
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          case (4)
             if (val == " ") then
                vtable(vcount)%level2 = 999
             else
                read(val,*,iostat=ierr) vtable(vcount)%level2
                if (ierr /= 0) then
                   write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                   stop
                endif
             endif
          case (5)
             vtable(vcount)%name = val
          case (6)
             vtable(vcount)%units = val
          case (7)
             vtable(vcount)%desc = val
          case (8)
             read(val,*,iostat=ierr) vtable(vcount)%g2_discp
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          case (9)
             read(val,*,iostat=ierr) vtable(vcount)%g2_cat
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          case (10)
             read(val,*,iostat=ierr) vtable(vcount)%g2_parm
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          case (11)
             read(val,*,iostat=ierr) vtable(vcount)%g2_levtyp
             if (ierr /= 0) then
                write(*,'("Vtable read problem, entry ", I4, " column ", I4)') vcount, j
                stop
             endif
          end select

       enddo BLOOP

       ! write(*,'(I4,I4,I4,I4,1x,A,1x,A,1x,A,I4,I4,I4,I4)') vtable(vcount)%g1_parm, vtable(vcount)%g1_levtyp, &
       !      vtable(vcount)%level1, vtable(vcount)%level2, trim(vtable(vcount)%name), &
       !      trim(vtable(vcount)%units), trim(vtable(vcount)%desc), vtable(vcount)%g2_discp, &
       !      vtable(vcount)%g2_cat, vtable(vcount)%g2_parm, vtable(vcount)%g2_levtyp

    enddo VLOOP

    vtable_count = vcount

  end subroutine read_vtable

!==============================================================================
!==============================================================================

  subroutine data_buffer_init(prev, current, post, file_template, remap_type, label, fatality)
    implicit none
    type (DataBuffer) :: prev, current, post
    character(len=256), dimension(MAXTEMPLATE), intent(in)  :: file_template
    character(len=*),  intent(in)  :: label
    character(len=*),  intent(in) :: remap_type
    integer, optional, intent(in) :: fatality
    prev%label    = label
    prev%hdate    = "0000-00-00_00:00:00"
    prev%flnm_template = file_template
    prev%remap_type = remap_type
    if (present(fatality)) then
       prev%fatality=fatality
    else
       prev%fatality=0
    endif
    current = prev
    post    = prev
  end subroutine data_buffer_init

!==============================================================================
!==============================================================================

  subroutine copy_data_buffer(out, in)
    !
    ! Copy the databuffer type from <in> to <out>
    !
    ! We do this to be explicit in allocating new memory for 
    ! pointer array <out%field>, and copying the data from 
    ! <in%field> to <out%field> (instead of merely pointing
    ! <out%field> => <in%field>
    implicit none
    type(DataBuffer), intent(out) :: out
    type(DataBuffer), intent(in)  :: in


    out%label = in%label
    out%units = in%units
    out%hdate = in%hdate
    out%flnm_template = in%flnm_template
    out%layer1 = in%layer1
    out%layer2 = in%layer2
    out%remap_type = in%remap_type
    out%fatality = in%fatality

    if (associated(in%field)) then
       allocate(out%field(size(in%field,1), size(in%field,2)))
       out%field = in%field
    else
       nullify(out%field)
    endif

    
  end subroutine copy_data_buffer

!==============================================================================
!==============================================================================

  subroutine process(input_date, current, prev, post, geo_em, expand_loop)
    use module_input_data_structure
    implicit none
    character(len=*), intent(in)    :: input_date
    type(DataBuffer), intent(inout) :: current
    type(DataBuffer), intent(inout) :: prev
    type(DataBuffer), intent(inout) :: post
    type (geo_em_type), intent(in)  :: geo_em
    integer, intent(in)             :: expand_loop

    type(input_data_type) :: datastruct
    type(input_data_type) :: Zdatastruct
    type(input_data_type) :: LANDSEAdatastruct

    real    :: xval

    integer :: ierr
    integer :: idts

    integer :: idim
    integer :: jdim

    character(len=256) :: teststring


    ! The fatality level in the DataBuffer structure indicates what sort
    ! of errors are fatal and what sort of errors we want to try to 
    ! recover from.
    ! 
    ! fatality==0 means that any problem is a fatal error, and we stop.
    !
    ! fatality==2 means that if we cannot find a matching file, and we
    ! cannot find files from which we may do temporal interpolation, we
    ! do not stop, but return a missing-data field.  The calling routine
    ! is responsible for filling in missing data.
    nullify(datastruct%data)
    nullify(zdatastruct%data)
    nullify(LANDSEAdatastruct%data)

    idim = geo_em%idim
    jdim = geo_em%jdim

    current%hdate = input_date(1:13)//":00:00"

    if (associated(current%field)) then
       deallocate(current%field)
       nullify(current%field)
    endif

    ! First, check if a post buffer matches the current date.
    if (post%hdate == current%hdate) then
       ! The post buffer matches the current date.  This is the data we want.

       call copy_data_buffer(current, post)
       if (associated(prev%field)) deallocate(prev%field)
       call copy_data_buffer(prev, post)

       deallocate(post%field)
       nullify(post%field)
       post%hdate = "0000-00-00_00:00:00"
       return
    endif

    ! Next, search for a GRIB file matching the current date.

    teststring = upcase(current%flnm_template(1))
    teststring = unblank(teststring)

    if ( teststring(1:9) == "CONSTANT:") then
       read(teststring(10:),*) xval
       allocate(current%field(idim,jdim))
       current%field = xval
       select case ( current%label )
       case ("WEASD")
          current%units = "kg/m^2"
          current%layer1 = -1.E36
          current%layer2 = -1.E36
       case ("CANWAT")
          current%units = "kg/m^2"
          current%layer1 = -1.E36
          current%layer2 = -1.E36
       case ("SKINTEMP")
          current%units = "K"
          current%layer1 = -1.E36
          current%layer2 = -1.E36
       case ("STEMP_1")
          current%units = "K"
          current%layer1 = 0.0
          current%layer2 = 0.1
       case ("STEMP_2")
          current%units = "K"
          current%layer1 = 0.1
          current%layer2 = 0.4
       case ("STEMP_3")
          current%units = "K"
          current%layer1 = 0.4
          current%layer2 = 1.0
       case ("STEMP_4")
          current%units = "K"
          current%layer1 = 1.0
          current%layer2 = 2.0
       case ("SMOIS_1")
          current%units = "m^3/m^3"
          current%layer1 = 0.0
          current%layer2 = 0.1
       case ("SMOIS_2")
          current%units = "m^3/m^3"
          current%layer1 = 0.1
          current%layer2 = 0.4
       case ("SMOIS_3")
          current%units = "m^3/m^3"
          current%layer1 = 0.4
          current%layer2 = 1.0
       case ("SMOIS_4")
          current%units = "m^3/m^3"
          current%layer1 = 1.0
          current%layer2 = 2.0
       case default
          write(*,'("Constant field not allowed for field ",A)') trim(current%label)
          stop
       end select

       return
    endif

    call grib_file_search_now(current, datastruct, ierr)

    if (ierr == 0) then

       !
       ! Attempt to fill in masked-out data in the original data array.
       !

       if(expand_loop > 0) call expand_9pt_input(datastruct%data,datastruct%nx, datastruct%ny, expand_loop)

       ! If this is air temperature data, we need to adjust to sea-level:
       ! This will later be adjusted back to the destination surface elevation.
       if (current%label == "T2D") then
          ! Get the source model terrain data file.
          Zcurrent%hdate = current%hdate
          call grib_file_search_now(Zcurrent, Zdatastruct, ierr)
          if (ierr /= 0) then
             stop "Source model terrain data not found"
          endif

          if ( .not. check_if_same_map(datastruct, Zdatastruct) ) then
             stop "1) Source model terrain dimensions do not match source model temperature dimensions"
          endif
	  where(Zdatastruct%data < 0.0) Zdatastruct%data = 0.0   ! Barlage 20140529
          datastruct%data = datastruct%data - ( -0.0065 * Zdatastruct%data )
          deallocate(Zdatastruct%data)
          nullify(Zdatastruct%data)
       endif

       ! If this field is soil temperature or moisture, fill in some water points
       ! with a smooth expansion of the land-point data.  We do this
       ! so that interpolation can be a little more sane.
       if ( (current%label(1:6) == "STEMP_") .or. (current%label(1:6) == "SMOIS_") ) then
          ! Get the source model Land/Sea mask data.
          LANDSEA%hdate = current%hdate
          call grib_file_search_now(LANDSEA, LANDSEAdatastruct, ierr)
          if (ierr /= 0) then
             print*, "Source model land/sea data not found; assuming a bitmap exists"
	     LANDSEAdatastruct%data = -1   ! Initialize LS mask to -1, if not available we assume bitmap Barlage
	  else
             where(LANDSEAdatastruct%data == 0) datastruct%data = -1e36
             deallocate(LANDSEAdatastruct%data)
          endif
! Barlage 20140529: comment the following and use expand_9pt to deal with missing values
!          call fillsm(datastruct%data, (LANDSEAdatastruct%data /= 0), datastruct%nx, datastruct%ny)

          where(datastruct%data < 0) datastruct%data = -1e36   ! This used for bitmap data Barlage 20150520

! Barlage 20140529: the following will probably do an additional expansion, but it won't hurt
          call expand_9pt_input(datastruct%data,datastruct%nx, datastruct%ny, expand_loop)
          nullify(LANDSEAdatastruct%data)
       endif

       ! remap the datastruct data to the model grid
       if (current%label == "RAINRATE") then
          allocate(current%field(idim, jdim))
          if (rainfall_interp == 0) then
             call interp_rainfall_nearest_neighbor(datastruct, current%field, geo_em%idim, geo_em%jdim, geo_em)
          else if (rainfall_interp == 1) then
             call interp_rainfall(datastruct, current%field, geo_em%idim, geo_em%jdim, geo_em)
             ! call another_interp_rainfall(datastruct, current%field, geo_em%idim, geo_em%jdim, geo_em)
          endif
       else
          ! This remap function allocates current%field and fills it.
          call remap(datastruct, geo_em, current)
       endif
       deallocate(datastruct%data)
       nullify(datastruct%data)

! Barlage 20140529: comment the following 
!       if ( (current%label(1:6) == "STEMP_") .or. (current%label(1:6) == "SMOIS_") ) then
!          where (geo_em%use == geo_em%iswater) current%field=-1.E36
!       endif

       ! Make the current data available as previous data, in preparation for the next time step.
       if (associated(prev%field)) deallocate(prev%field)
       call copy_data_buffer(prev, current)

       ! Clear post
       if (associated(post%field)) then
          deallocate(post%field)
          nullify(post%field)
       endif
       post%hdate = "0000-00-00_00:00:00"

       ! We've got the data we wanted, so get out of here.
       return

    endif
    
    ! We did not find data.  Let's try to temporally interpolate.

    ! A "prev" buffer must exist for us.  Check that.

    if (prev%hdate ==  "0000-00-00_00:00:00") then

       if (current%fatality == 2) then
          allocate(current%field(idim, jdim))
          current%field = -1.E36
          write(*,'(13x, ":  Prior data missing for ", A, ".  Returning missing-data field.")') &
               trim(current%label)
          return
       endif

       write(*,'("Field label= ",A)') trim(current%label)
       write(*,'("No previous data.")') 
       stop
    endif

    ! The "prev" buffer must be recent.  Check that
    call geth_idts (current%hdate, prev%hdate, idts)
    if (idts > 43200) then

       if (current%fatality == 2) then
          allocate(current%field(idim, jdim))
          current%field = -1.E36
          if (associated(prev%field)) then
             deallocate(prev%field)
             nullify(prev%field)
          endif
          prev%hdate = "0000-00-00_00:00:00"
          write(*,'(13x, ":  Prior data is out-of-date for ", A, ".  Returning missing-data field.")') &
               trim(current%label)
          return
       endif

       write(*,'("Previous data is out of date.")')
       stop
    endif

    ! Check for a "post" buffer.

    if (post%hdate > current%hdate) then
       call geth_idts(post%hdate, prev%hdate, idts)
       if (idts > 43200) then

          if (current%fatality == 2) then
             allocate(current%field(idim, jdim))
             current%field = -1.E36
             if (associated(prev%field)) then
                deallocate(prev%field)
                nullify(prev%field)
             endif
             prev%hdate = "0000-00-00_00:00:00"
             write(*,'(13x, ":  Time range for interpolation of ", A, " is too large.  ",&
                  &"Returning missing-data field.")') &
                  trim(current%label)
             return
          endif
          stop
       endif

       if (current%label == "RAINRATE") then
          ! Don't temporally interpolate the rain rate.  
          allocate(current%field(size(prev%field,1), size(prev%field,2)))
          ! Take the "post" field, because that field should be the accumulation
          ! between "prev" and "post"
          current%field = post%field
       else
          call temporal_interpolation(prev, post, current)
       endif
       ! We have the data we want, so we can exit.
       return
    endif

    ! No post buffer, so we must read some new data into a post buffer

    call grib_file_search_future(current, post, datastruct, ierr)

    if (ierr /= 0) then

       if (current%fatality == 2) then
          allocate(current%field(idim, jdim))
          current%field = -1.E36
          if (associated(prev%field)) then
             deallocate(prev%field)
             nullify(prev%field)
          endif
          prev%hdate = "0000-00-00_00:00:00"
          write(*,'(13x, ":  No later data for interpolation of ", A, ".  Returning missing-data field.")') &
               trim(current%label)
          return
       endif

       write(*,'("We could not find later data to interpolate")')
       stop
    endif

    ! If this is air temperature data, we need to adjust to sea-level:
    ! This will later be adjusted back to the destination surface elevation.
    if (current%label == "T2D") then
       ! Get the source model terrain data file.
       Zcurrent%hdate = post%hdate
       call grib_file_search_now(Zcurrent, Zdatastruct, ierr)
       if (ierr /= 0) then
          stop "Source model terrain data not found"
       endif
       if ( .not. check_if_same_map(datastruct, Zdatastruct) ) then
          stop "2) Source model terrain dimensions do not match source model temperature dimensions"
       endif
       where(Zdatastruct%data < 0.0) Zdatastruct%data = 0.0   ! Barlage 20140529
       datastruct%data = datastruct%data - ( -0.0065 * Zdatastruct%data )
       deallocate(Zdatastruct%data)
       nullify(Zdatastruct%data)
    endif

    ! remap the datastruct data to the model grid

    ! This remap function allocates post%field and fills it.
    call remap(datastruct, geo_em, post)
    deallocate(datastruct%data)
    nullify(datastruct%data)

    if (current%label == "RAINRATE") then
       ! Don't temporally interpolate the rain rate.  
       ! Simply carry the previous value forward.
       allocate(current%field(size(prev%field,1), size(prev%field,2)))
       current%field = post%field
    else
       call temporal_interpolation(prev, post, current)
    endif

    ! We have the data we want, and prev and post are both up-to-date, 
    ! so we can exit.

  end subroutine process

!==============================================================================
!==============================================================================

  subroutine expand_9pt_input(data, nx, ny, maxloop)
  
  ! This routine checks for missing data in the input forcing and 
  !  expands using a 9pt average; Added to deal with input data such
  !  as NLDAS which doesn't have any values over water
  
    implicit none
    integer,                    intent(in)      :: nx
    integer,                    intent(in)      :: ny
    real,    dimension(nx, ny), intent(inout)   :: data
    integer,                    intent(in)      :: maxloop

    integer :: i, k, ilo, ihi, klo, khi, loop, testnum
    real, dimension(nx,ny) :: hold

    do loop = 1, maxloop
       hold = data
       do i = 1, nx
          do k = 1, ny
             if (hold(i,k) < -1e10 ) then
                ilo = max( 1,i-1)
                ihi = min(nx,i+1)
                klo = max( 1,k-1)
                khi = min(ny,k+1)
                testnum = count(hold(ilo:ihi,klo:khi) > -1e10)
                if(testnum > 0) then
                   data(i,k) = sum(hold(ilo:ihi,klo:khi), hold(ilo:ihi,klo:khi) > -1e10)/testnum
                endif
             endif
          enddo
       enddo
    enddo

  end subroutine expand_9pt_input

!==============================================================================
!==============================================================================

  subroutine remap(datastruct, geo_em, buff)
    use module_input_data_structure
    implicit none
    type(input_data_type), intent(in)  :: datastruct
    type (geo_em_type), intent(in) :: geo_em
    type(DataBuffer), intent(inout)  :: buff

    integer :: i, j
    integer :: idim, jdim
    real, allocatable, dimension(:,:) :: etax, etay
    real :: east_longitude

    buff%layer1 = datastruct%layer1
    buff%layer2 = datastruct%layer2

    idim = geo_em%idim
    jdim = geo_em%jdim
    allocate(buff%field(idim,jdim))
    allocate(etax(idim,jdim))
    allocate(etay(idim,jdim))

    do i = 1, idim
       do j = 1, jdim
          call latlon_to_ij(datastruct%proj, geo_em%lat(i,j), geo_em%lon(i,j), etax(i,j), etay(i,j))

          if (buff%remap_type=="bint") then
             buff%field(i,j) = bint_p(datastruct%data, datastruct%nx, datastruct%ny, etax(i,j), etay(i,j))
          else if (buff%remap_type == "4pt") then
             buff%field(i,j) = four_point_p(datastruct%data, datastruct%nx, datastruct%ny, etax(i,j), etay(i,j))
          else if (buff%remap_type == "16pt") then
             buff%field(i,j) = wt_sixteen_pt_average(datastruct%data, datastruct%nx, datastruct%ny, &
	                                 etax(i,j), etay(i,j),-1E+36,-1E+36)
          else
             print*, "'"//trim(buff%remap_type)//"'"
             stop "remap type"
          endif

       enddo
    enddo
    deallocate(etax)
    deallocate(etay)


  end subroutine remap

!==============================================================================
!==============================================================================

  subroutine grib_file_search_future(current, post, datastruct, ierr)
    use module_input_data_structure
    implicit none
    type(DataBuffer), intent(inout) :: current
    type(DataBuffer), intent(inout) :: post
    type(input_data_type), intent(out) :: datastruct
    integer, intent(out) :: ierr

    character(len=13) :: kdate
    integer :: i, j
    character(len=256) :: flnm

    logical :: lexist

    nullify(datastruct%data)

    ierr = 1
    kdate = current%hdate(1:13)

    DATE_SEEK_LOOP : do i = 1, 12

       TEMPLATE_LOOP : do j = 1, MAXTEMPLATE
          if (current%flnm_template(j) /= " ") then
             flnm = current%flnm_template(j)

             call fill_template(flnm, kdate)

             write(*,'(A)') "             "//":  Checking for file '"//trim(flnm)//"'"

             inquire(file=trim(flnm), exist=lexist)
             if ( .not. lexist ) then
                inquire(file=trim(flnm)//".bz2", exist=lexist)
                if (lexist) then
                   flnm = trim(flnm)//".bz2"
                endif
             endif

             if (lexist) then
                write(*,'(A)') "             "//":  Found file "//trim(flnm)
                ierr = 0
                exit DATE_SEEK_LOOP
             endif
          endif
       enddo TEMPLATE_LOOP

       call geth_newdate(kdate, kdate, 1)

    enddo DATE_SEEK_LOOP

    ! If we haven't found any matching data yet, then get out of here.
    if (ierr == 1) return

    call get_single_datastruct_from_grib(trim(flnm), kdate, datastruct, ierr)
    post%hdate = kdate//":00:00"
    post%units = datastruct%units

  end subroutine grib_file_search_future

!==============================================================================
!==============================================================================

  subroutine grib_file_search_now(current, datastruct, ierr)
    use module_input_data_structure
    implicit none
    type(DataBuffer), intent(inout)  :: current
    type(input_data_type), intent(out) :: datastruct
    integer, intent(out) :: ierr
    character(len=256) :: flnm
    logical :: lexist
    integer :: j
    character(len=13) :: kdate

    kdate = current%hdate(1:13)

    ierr = 1

    TEMPLATE_LOOP : do j = 1, MAXTEMPLATE
       if (current%flnm_template(j) /= " ") then
          flnm = current%flnm_template(j)

          call fill_template(flnm, kdate)

          write(*,'(A)') "             "//":  Checking for file '"//trim(flnm)//"'"

          inquire(file=trim(flnm), exist=lexist)
          if ( .not. lexist ) then
             inquire(file=trim(flnm)//".bz2", exist=lexist)
             if (lexist) then
                flnm = trim(flnm)//".bz2"
             endif
          endif

          if (lexist) then
             write(*,'(A)') "             "//":  Found file "//trim(flnm)
             ierr = 0
             exit TEMPLATE_LOOP
          endif
       endif
    enddo TEMPLATE_LOOP
    if (ierr == 1) return

    nullify(datastruct%data)  ! Barlage: move from above

    call get_single_datastruct_from_grib(trim(flnm), kdate, datastruct, ierr)
    current%units = datastruct%units

    if ( current%label /= datastruct%field ) then
       write(*,'(/,1x,80("*"))')
       write(*,'(" *****  PROBLEM:  Requested field name does not match the name in the Vtable entry.")')
       write(*,'(" ***** ")')
       write(*,'(" *****      Requested field name: ''",A,"''")') trim(current%label)
       write(*,'(" *****      Field name in the Vtable entry:  ''",A,"''")') trim(datastruct%field)
       write(*,'(" ***** ")')
       write(*,'(" *****  Please check your VTable entries and filename templates in your namelist")')
       write(*,'(" *****  to be sure you are getting the fields you think you are getting.")')
       write(*,'(1x,80("*"),/)')
       stop
    endif

  end subroutine grib_file_search_now

!==============================================================================
!==============================================================================

  subroutine temporal_interpolation(prev, post, current)
    implicit none
    type(DataBuffer), intent(in) :: prev
    type(DataBuffer), intent(in) :: post
    type(DataBuffer), intent(inout) :: current

    integer :: xdiff
    integer :: tdiff
    real    :: fraction

    call geth_idts(current%hdate, prev%hdate, xdiff)
    call geth_idts(post%hdate, prev%hdate, tdiff)

    fraction = real(xdiff)/real(tdiff)

    allocate(current%field(size(prev%field,1), size(prev%field,2)))
    current%field = (prev%field)*(1.0-fraction) + (post%field)*(fraction)

!KWM    if (prev%layer1 /= post%layer1) then
!KWM       print*, 'prev%layer1  = ', prev%layer1
!KWM       print*, 'post%layer1  = ', post%layer1
!KWM       stop "layer1 mismatch"
!KWM    endif
!KWM    if (prev%layer2 /= post%layer2) then
!KWM       print*, 'prev%layer2  = ', prev%layer2
!KWM       print*, 'post%layer2  = ', post%layer2
!KWM       stop "layer2 mismatch"
!KWM    endif
!KWM    current%layer1 = prev%layer1
!KWM    current%layer2 = prev%layer2

  end subroutine temporal_interpolation

!==============================================================================
!==============================================================================

  subroutine output_databuffer(ncid, buff)
    implicit none
    integer,              intent(in) :: ncid
    type (DataBuffer),    intent(in) :: buff
    ! Wrapper around call to output_to_netcdf
    call output_to_netcdf(ncid, buff%label, buff%units, buff%field, &
         size(buff%field,1), size(buff%field,2))
  end subroutine output_databuffer

!==============================================================================
!==============================================================================

  subroutine get_single_datastruct_from_grib(gribflnm, kdate, datastruct, ierr)
    use module_grib
    use kwm_string_utilities
    use module_input_data_structure
    implicit none
    character(len=*), intent(in) :: gribflnm, kdate
    type(input_data_type), intent(out) :: datastruct
    integer, intent(out) :: ierr

    character(len=256) :: flnm
    integer(kind=8) :: gribunit
    integer :: istat

    !-------------------------------------------------------------------------
    nullify(datastruct%data)

    flnm = gribflnm

    call fill_template(flnm, kdate)

    ! Open the unit and read the first GRIB record
    call gribopen(flnm, gribunit, ierr);
    if (ierr /= 0) then
       if (ierr == 2) then
          write(*, '("File does not exist: ",A)') trim(flnm)
       else
          write(*, '("Undetermined problem opening file: ", A)') trim(flnm)
       endif
       return
       stop "get_single_datastruct_from_grib"
    endif
    if (associated(datastruct%data)) then
       deallocate(datastruct%data)
       nullify(datastruct%data)
    endif
    call read_grib_unit(gribunit, datastruct, ierr, trim(flnm))
    if (ierr /= 0) then
       print*, 'Returning error flag from get_single_datastruct_from_grib (1)'
       print*, 'gribunit = ', gribunit
       print*, 'flnm = ', trim(flnm)
       print*, 'ierr = ', ierr
       if (associated(datastruct%data)) then
          deallocate(datastruct%data)
          nullify(datastruct%data)
       endif
       return
    endif
    call gribclose(gribunit)

  end subroutine get_single_datastruct_from_grib

!==============================================================================
!==============================================================================

  subroutine read_grib_unit(nunit, datastruct, ierr, info)
    use module_grib
    use module_input_data_structure
    implicit none
    integer(kind=8), intent(in) :: nunit
    type(input_data_type), intent(out) :: datastruct
    integer :: ierr, i, j
    real :: rb, xdum
    real :: oldmax
    real :: newmax
    integer :: astat
    character(len=*), intent(in), optional :: info

    type(GribStruct)  :: grib
    character(len=64)  :: name
    character(len=256) :: units
    character(len=256) :: description

    ! Returned from grib_level_information
    character(len=256) :: level_type
    character(len=256) :: level_units
    real               :: level_value
    real               :: level2_value

    ! Returned from grib_time_information
    character(len=19)  :: reference_date
    character(len=19)  :: valid_date
    character(len=256) :: process
    character(len=256) :: processing
    integer            :: p1_seconds
    integer            :: p2_seconds

    real, parameter :: grrth = 6370.949
    real, external  :: tand
    real, external  :: sind
    real, external  :: cosd

    !
    ! Get a grib field, unpacking all header information.
    !
    nullify(grib%buffer)
    nullify(grib%bitmap)
    nullify(grib%array)
    nullify(grib%sec7%floated)
    nullify(datastruct%data)

    call grib_next_field(nunit, grib, ierr)
    if (ierr /= 0) then
       write(*, '("Returning error from read_grib_unit:  nunit = ", I3, "  ierr = ", I3)') nunit, ierr
       if (present(info)) print*, info
       return
    endif

    !
    ! Match the grib record we've just read with one of our grib table entries.
    !
    if (grib%edition == 1) then
       G1SEARCH : do j = 1, vtable_count
          if ( (grib%g1sec1%parameter == vtable(j)%g1_parm) .and. &
               (grib%g1sec1%leveltyp  == vtable(j)%g1_levtyp) .and. &
               (grib%g1sec1%levelval  == vtable(j)%level1) ) then
             if ( (grib%g1sec1%level2val  == vtable(j)%level2) .or. &
                  (grib%g1sec1%level2val < -1.E25) .or. &
                  (vtable(j)%level2 == 999) ) then
                ! print*, 'Parameter match:  ', &
                !      grib%g1sec1%parameter, grib%g1sec1%leveltyp, grib%g1sec1%levelval, grib%g1sec1%level2val
                datastruct%field  = vtable(j)%name
                datastruct%desc   = vtable(j)%desc
                datastruct%units  = vtable(j)%units
                write(*, '(A, "  GRIB Editon 1")') datastruct%field
                exit G1SEARCH
             endif
          endif
          if (j == vtable_count) then
             write(*,'(/," ***** ERROR *****")')
             write(*,'(" *****       GRIB Edition 1 data does not match a Vtable entry")')
             print*, grib%g1sec1%parameter, grib%g1sec1%leveltyp, grib%g1sec1%levelval, grib%g1sec1%level2val
             stop "Edition 1"
          endif
       enddo G1SEARCH
    else if (grib%edition == 2) then
       G2SEARCH : do j = 1, vtable_count
          if ( (grib%discipline == vtable(j)%g2_discp) .and. &
               (grib%sec4%parameter_category == vtable(j)%g2_cat) .and. &
               (grib%sec4%parameter_number == vtable(j)%g2_parm) .and. &
               (grib%sec4%ltype1  == vtable(j)%g2_levtyp) .and. &
               (grib%sec4%lvalue1  == vtable(j)%level1) ) then
             if ( (grib%sec4%lvalue2  == vtable(j)%level2) .or. &
                  (grib%sec4%lvalue2 < -1.E25) .or. &
                  (vtable(j)%level2 == 999) ) then
                ! print*, 'Parameter match:  ', &
                !      grib%discipline, grib%sec4%parameter_category, grib%sec4%ltype1, grib%sec4%lvalue1, grib%sec4%lvalue2
                datastruct%field  = vtable(j)%name
                datastruct%desc   = vtable(j)%desc
                datastruct%units  = vtable(j)%units
                write(*, '(A, "  GRIB Editon 2")') datastruct%field
                exit G2SEARCH
             endif
          endif
          if (j == vtable_count) then
             write(*,'(/," ***** ERROR *****")')
             write(*,'(" *****       GRIB Edition 2 data does not match a Vtable entry")')
             print*, grib%discipline, grib%sec4%parameter_category, grib%sec4%parameter_number, &
                  grib%sec4%ltype1, grib%sec4%lvalue1, grib%sec4%lvalue2
             stop "Edition 2"
          endif
       enddo G2SEARCH
    endif

    call grib_time_information(grib, reference_date, valid_date, process, processing, p1_seconds, p2_seconds)
    datastruct%hdate = valid_date

    datastruct%layer1 = -1.E36
    datastruct%layer2 = -1.E36

    description = " "

! Barlage: is it necessary to read external grib tables? why not just read namelist table for this info 20150518
!   
!    call grib_parameter_text_information(grib, name, units, description)
! Barlage: move assignment up 20150518
!    datastruct%desc   = description
!    datastruct%units  = units

    ! print*, 'description = "' // trim(description) // '"'

    call grib_level_information(grib, level_type, level_units, level_value, level2_value)

    datastruct%layer1 = level_value
    datastruct%layer2 = level2_value

    call grib_map_information(grib)

    datastruct%nx = grib%mapinfo%nx
    datastruct%ny = grib%mapinfo%ny
    
    call map_init(datastruct%proj)
!KWM    datastruct%proj%lat1 = grib%mapinfo%lat1
!KWM    if (grib%mapinfo%lon1 > 180) then
!KWM       datastruct%proj%lon1 = grib%mapinfo%lon1-360
!KWM    else
!KWM       datastruct%startlon = grib%mapinfo%lon1
!KWM    endif

    if (grib%mapinfo%hproj == "CE") then

       call map_set(PROJ_LATLON, datastruct%proj, lat1=grib%mapinfo%lat1, lon1=grib%mapinfo%lon1, &
            latinc=grib%mapinfo%dy, loninc=grib%mapinfo%dx, knowni=1.0, knownj=1.0)
       
    else if (grib%mapinfo%hproj == "LC") then

       call map_set(PROJ_LC, datastruct%proj, lat1=grib%mapinfo%lat1, lon1=grib%mapinfo%lon1, &
            knowni=1.0, knownj=1.0, truelat1=grib%mapinfo%truelat1, truelat2=grib%mapinfo%truelat2, &
            stdlon=grib%mapinfo%xlonc, dx=grib%mapinfo%dx*1.E3)

    else if (grib%mapinfo%hproj == "ST") then

       call map_set(PROJ_PS, datastruct%proj, lat1=grib%mapinfo%lat1, lon1=grib%mapinfo%lon1, truelat1=grib%mapinfo%truelat1, &
            knowni=1.0, knownj=1.0, stdlon=grib%mapinfo%xlonc, dx=grib%mapinfo%dx*1.E3)

    else

       write(*,'("Unrecognized grib%mapinfo%hproj:  ", A2)') grib%mapinfo%hproj
       stop

    endif

    if (associated(datastruct%data)) then
       deallocate(datastruct%data)
       nullify(datastruct%data)
    endif
    allocate(datastruct%data(datastruct%nx,datastruct%ny), stat=astat)
    if (astat /= 0) stop "Problem (A) allocating datastruct%data"

    call gribdata(grib)
    datastruct%data = grib%array
    call deallogrib(grib)

    ! If the data are from GCIP SRB archives, they're at 15 minutes off the hour.
    ! Ignore that 15-minute offset in that case, and put the date right on the hour.

    if (datastruct%field == "SWDOWN") then
       if (rescale_shortwave) then
          call rescale_sw_time_offset(datastruct)
       endif
       datastruct%hdate(15:16) = "00"
       ! TEST:  Set zero data values to missing data for GCIP SW fields
       ! where (datastruct%data <= 0) datastruct%data = -1.E36 
    endif

!MB: want mm units in v3.7
!KWM    if (description == "Plant Canopy Surface Water") then
!    if (datastruct%field == "CANWAT") then
!       ! Convert canwat from kg m{-2} (that is, mm) to m
!       datastruct%data = datastruct%data * 1.E-3
!       datastruct%units = "m"
!    endif

    if (datastruct%field(1:6) == "SMOIS_") then
       ! If units are kg m{-2} (that is, mm), convert to volumetric
     if ( (datastruct%units == "kg/m^2") .or. (datastruct%units == "mm") ) then
       write(*,*) "Converting soil water content to volumetric using thickness[m]: ", &
           (datastruct%layer2 - datastruct%layer1)
       datastruct%data = datastruct%data * 1.E-3 / (datastruct%layer2 - datastruct%layer1)
       datastruct%units = "m^3/m^3"
     elseif (datastruct%units == "gldas") then  ! hack to take care of bad units in GLDAS MBv3.7
       if(datastruct%field(1:7) == "SMOIS_1") datastruct%layer1 = 0
       if(datastruct%field(1:7) == "SMOIS_1") datastruct%layer2 = 0.1
       if(datastruct%field(1:7) == "SMOIS_2") datastruct%layer1 = 0.1
       if(datastruct%field(1:7) == "SMOIS_2") datastruct%layer2 = 0.4
       if(datastruct%field(1:7) == "SMOIS_3") datastruct%layer1 = 0.4
       if(datastruct%field(1:7) == "SMOIS_3") datastruct%layer2 = 1.0
       if(datastruct%field(1:7) == "SMOIS_4") datastruct%layer1 = 1.0
       if(datastruct%field(1:7) == "SMOIS_4") datastruct%layer2 = 2.0
       write(*,*) "Converting soil water content to volumetric using thickness[m]: ", &
           (datastruct%layer2 - datastruct%layer1)
       datastruct%data = datastruct%data * 1.E-3 / (datastruct%layer2 - datastruct%layer1)
       datastruct%units = "m^3/m^3"
     endif
    endif

    ! print*, 'Description = "'//trim(description)//'"'
    ! if (description == "Total precipitation") then
    if (datastruct%field == "RAINRATE") then
       ! print*, 'datastruct%units = ', datastruct%units
       ! Convert from kg/m^2 (that is, mm) in <nn> hours to mm/s
       if ( (datastruct%units == "kg/m^2") .or. (datastruct%units == "mm") ) then
!KWM          print*, 'Time information:  '
!KWM          print*, '                   Reference Date ' // reference_date
!KWM          print*, '                   Reference Date ' // valid_date
!KWM          print*, '                                  ' // trim(process)
!KWM          print*, '                                  ' // trim(processing)
!KWM          print*, '                               P1 ', p1_seconds
!KWM          print*, '                               P2 ', p2_seconds
          if (processing(1:12) == "Accumulation") then
             oldmax = maxval(datastruct%data, mask=(datastruct%data > -1.E25))
             write(*,'(13x, "Maxval adjusted from ", F12.6)', advance="no") oldmax
             where (datastruct%data > -1.E25) 
                datastruct%data = datastruct%data * (1.0 / float(p2_seconds - p1_seconds))
             endwhere
             newmax = maxval(datastruct%data, mask=(datastruct%data > -1.E25))
             write(*,'(" to ", F12.6, ":    factor of ", I8)') newmax, NINT(oldmax/newmax)
             ! Change the units to mm/s, reflecting the rescaling we just did.
             datastruct%units = "mm/s"
          else 
             stop "Precip Problem A?"
          endif
       elseif ( (datastruct%units == "kg/m^2/s") ) then ! For example, GLDAS; MB v3.7
          datastruct%units = "mm/s"
       else
          stop "Precip Problem B?"
       endif
    endif

  end subroutine read_grib_unit

!==============================================================================
!==============================================================================

  logical function check_if_same_map(A, B) result (lval)
    ! Check two DATASTRUCT structures to see if they have the same grid/map.
    use module_input_data_structure
    implicit none
    type(input_data_type), intent(in) :: A
    type(input_data_type), intent(in) :: B

    lval = .TRUE.

    if (A%proj%code /= B%proj%code)    lval = .FALSE.
    if (A%nx       /= B%nx)       lval = .FALSE.
    if (A%ny       /= B%ny)       lval = .FALSE.
    if (abs(A%proj%lat1 - B%proj%lat1) > 1.E-4) lval = .FALSE.
    if (abs(A%proj%lon1 - B%proj%lon1) > 1.E-4) lval = .FALSE.
    if ((A%proj%latinc > -1.E25) .and. (B%proj%latinc > -1.E25)) then
       if (abs(A%proj%latinc - B%proj%latinc) > 1.E-4) lval = .FALSE.
    endif
    if ((A%proj%loninc > -1.E25) .and. (B%proj%loninc > -1.E25)) then
       if (abs(A%proj%loninc - B%proj%loninc) > 1.E-4) lval = .FALSE.
    endif
    if ((A%proj%dx > -1.E25) .and. (B%proj%dx > -1.E25)) then
       if (abs(A%proj%dx - B%proj%dx) > 1.E-4) lval = .FALSE.
    endif
    if ((A%proj%dy > -1.E25) .and. (B%proj%dy > -1.E25)) then
       if (abs(A%proj%dy - B%proj%dy) > 1.E-4) lval = .FALSE.
    endif
    if ((A%proj%stdlon > -1.E25) .and. (B%proj%stdlon > -1.E25)) then
       if (abs(A%proj%stdlon  - B%proj%stdlon) > 1.E-4)   lval = .FALSE.
    endif
    if ((A%proj%truelat1 > -1.E25) .and. (B%proj%truelat1 > -1.E25)) then
       if (abs(A%proj%truelat1 - B%proj%truelat1) > 1.E-4) lval = .FALSE.
    endif
    if ((A%proj%truelat2 > -1.E25) .and. (B%proj%truelat2 > -1.E25)) then
       if (abs(A%proj%truelat2 - B%proj%truelat2) > 1.E-4) lval = .FALSE.
    endif

    if (.not. lval) then
       write(*, '("CHECK_IF_SAME_MAP:")')
       write(*, '("     proj_code= ", I12, I12)') A%proj%code, B%proj%code
       write(*, '("     nx       = ", I12, I12)') A%nx, B%nx
       write(*, '("     ny       = ", I12, I12)') A%ny, B%ny
       write(*, '("     startlat = ", F20.12, F20.12)') A%proj%lat1, B%proj%lat1
       write(*, '("     startlon = ", F20.12, F20.12)') A%proj%lon1, B%proj%lon1
       write(*, '("     deltalat = ", F20.12, F20.12)') A%proj%latinc, B%proj%latinc
       write(*, '("     deltalon = ", F20.12, F20.12)') A%proj%loninc, B%proj%loninc
       write(*, '("     dx       = ", F20.12, F20.12)') A%proj%dx, B%proj%dx
       write(*, '("     dy       = ", F20.12, F20.12)') A%proj%dy, B%proj%dy
       write(*, '("     xlonc    = ", F20.12, F20.12)') A%proj%stdlon, B%proj%stdlon
       write(*, '("     truelat1 = ", F20.12, F20.12)') A%proj%truelat1, B%proj%truelat1
       write(*, '("     truelat2 = ", F20.12, F20.12)') A%proj%truelat2, B%proj%truelat2
    endif

  end function check_if_same_map

!==============================================================================
!==============================================================================

end program create_forcing

!==============================================================================
!==============================================================================

subroutine interpolate_vegetation(name, date, idim, jdim, vegin, vegout)
  implicit none
  character(len=*),              intent(in)  :: name
  character(len=*),              intent(in)  :: date
  integer,                       intent(in)  :: idim, jdim
  real, dimension(idim,jdim,12), intent(in)  :: vegin
  real, dimension(idim,jdim)   , intent(out) :: vegout

  integer :: imo
  integer :: imo2
  integer :: imody
  real, allocatable, dimension(:,:) :: xdum, xdum2

  integer, parameter, dimension(12) :: mday = (/31,28,31,30,31,30,31,31,30,31,30,31/)

  ! Vegetation Fraction field

  read(date(6:10), '(I2,1x,I2)') imo, imody

  if (imody == 15) then
     vegout = vegin(:,:,imo)
  else if (imody > 15) then
     allocate(xdum(idim,jdim), xdum2(idim,jdim))
     xdum  = vegin(:,:,imo)
     xdum2 = vegin(:,:,mod(imo,12)+1)
     vegout = xdum + float(imody-15)/float(mday(imo))*(xdum2-xdum)
     deallocate(xdum, xdum2)
  else if (imody < 15) then
     allocate(xdum(idim,jdim), xdum2(idim,jdim))
     xdum2  = vegin(:,:,imo)
     if (imo == 1) then
        imo2 = 12
     else
        imo2 = imo - 1
     endif
     xdum   = vegin(:,:,imo2)

     vegout = xdum + float(mday(imo2)-(15-imody)) / float(mday(imo2)) &
          *(xdum2-xdum)
     deallocate(xdum, xdum2)
     if(trim(name) == "VEGFRA") then
       where (vegout <= 0) vegout = 1.E-2 !???
     end if
  endif
end subroutine interpolate_vegetation

!==============================================================================
!==============================================================================

subroutine fill_template(string, date)
  use kwm_string_utilities
  use kwm_date_utilities
  implicit none
  character(len=*), intent(inout) :: string
  character(len=*), intent(in)    :: date

  character(len=2)  :: hh
  character(len=13) :: dd
  character(len=3)  :: hnn
  integer           :: nn
  integer           :: idx

  call strrep(string, "<YYYY>", date(1:4))
  call strrep(string, "<MM>",   date(6:7))
  call strrep(string, "<DD>",   date(9:10))
  call strrep(string, "<HH>",   date(12:13))
  call strrep(string, "<date>", date(1:4)//date(6:7)//date(9:10)//date(12:13))

  !
  ! Build the filenames for analyses in range 0-(minus)12h
  !
  if ( index(string, "<init+12>") > 0) then
     hh = date(12:13)
     if (hh == "00") then
        dd = date
     elseif (hh <= "12") then
        dd=date(1:11)//"12"
     else
        dd=date(1:11)//"00"
        call geth_newdate(dd, dd, 24)
     endif
     call strrep(string, "<init+12>", dd(1:4)//dd(6:7)//dd(9:10)//dd(12:13))
  endif

!
!  Build the filenames for forecasts in ranges 0-12h, 12-24h, 24-36h, etc.
!

  idx = index(string, "<init-")
  if (idx > 0) then
     hnn = string(idx+5:idx+7)
     read(hnn,*) nn
     call geth_newdate(dd, date, (nn+12))
     hh = dd(12:13)
     if (hh == "00") then
        call geth_newdate(dd, dd, -12)
     elseif (hh <= "12") then
        dd=dd(1:11)//"00"
     else
        dd=dd(1:11)//"12"
     endif
     call strrep(string, "<init"//hnn//">", dd(1:4)//dd(6:7)//dd(9:10)//dd(12:13))
  endif

end subroutine fill_template

!==============================================================================
!==============================================================================

subroutine open_netcdf_for_output(output_flnm, ncid, version, ix, jx, geo_em, init)
  use module_geo_em
  implicit none
  character(len=*), intent(in) :: output_flnm
  character(len=*), intent(in) :: version
  integer, intent(in) :: ix, jx
  integer, intent(out) :: ncid
  type (geo_em_type), intent(in) :: geo_em
  logical, intent(in) :: init

  integer :: ierr, dimid
  integer, parameter :: datestrlen = 19

      ierr = nf90_create(trim(output_flnm), NF90_WRITE, ncid)
  call error_handler(ierr, "Problem nf90_create: "//trim(output_flnm))

  ierr = nf90_def_dim(ncid, "Time", NF90_UNLIMITED, dimid)
  call error_handler(ierr, "Problem nf90_def_dim Time")

  ierr = nf90_def_dim(ncid, "DateStrLen", datestrlen, dimid)
  call error_handler(ierr, "Problem nf90_def_dim DateStrLen")

  ierr = nf90_def_dim(ncid, "west_east", ix, dimid)
  call error_handler(ierr, "Problem nf90_def_dim west_east")

  ierr = nf90_def_dim(ncid, "south_north", jx, dimid)
  call error_handler(ierr, "Problem nf90_def_dim south_north")

  if (init) then

    ierr = nf90_def_dim(ncid, "soil_layers_stag", 4, dimid)
    call error_handler(ierr, "Problem nf90_def_dim soil_layers_stag")

  end if

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "TITLE", "OUTPUT FROM CONSOLIDATE_GRIB "//version)
  call error_handler(ierr, "Problem nf90_put_att TITLE")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "missing_value", -1.E36)
  ierr = nf90_put_att(ncid, NF90_GLOBAL, "_FillValue", -1.E36)
  call error_handler(ierr, "Problem nf90_put_att missing_value")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "WEST-EAST_GRID_DIMENSION", ix+1)
  call error_handler(ierr, "Problem nf90_put_att WEST-EAST_GRID_DIMENSION")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "SOUTH-NORTH_GRID_DIMENSION", jx+1)
  call error_handler(ierr, "Problem nf90_put_att SOUTH-NORTH_GRID_DIMENSION")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "DX", geo_em%proj%dx)
  call error_handler(ierr, "Problem nf90_put_att DX")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "DY", geo_em%proj%dx)
  call error_handler(ierr, "Problem nf90_put_att DY")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "TRUELAT1", geo_em%proj%truelat1)
  call error_handler(ierr, "Problem nf90_put_att TRUELAT1")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "TRUELAT2", geo_em%proj%truelat2)
  call error_handler(ierr, "Problem nf90_put_att TRUELAT2")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "LA1", geo_em%proj%lat1)
  call error_handler(ierr, "Problem nf90_put_att LA1")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "LO1", geo_em%proj%lon1)
  call error_handler(ierr, "Problem nf90_put_att LO1")

!KWM  ierr = nf90_put_att(ncid, NF90_GLOBAL, "LA2", geo_em%la2)
!KWM  call error_handler(ierr, "Problem nf90_put_att LA2")

!KWM  ierr = nf90_put_att(ncid, NF90_GLOBAL, "LO2", geo_em%lo2)
!KWM  call error_handler(ierr, "Problem nf90_put_att LO2")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "STAND_LON", geo_em%proj%stdlon)
  call error_handler(ierr, "Problem nf90_put_att STAND_LON")

  ierr = nf90_put_att(ncid, NF90_GLOBAL, "MAP_PROJ", geo_em%proj%code)
  call error_handler(ierr, "Problem nf90_put_att MAP_PROJ")
 
  if (init) then

    ierr = nf90_put_att(ncid, NF90_GLOBAL, "GRID_ID", geo_em%grid_id)
    call error_handler(ierr, "Problem nf90_put_att GRID_ID")

    ierr = nf90_put_att(ncid, NF90_GLOBAL, "ISWATER", geo_em%iswater)
    call error_handler(ierr, "Problem nf90_put_att ISWATER")
  
    ierr = nf90_put_att(ncid, NF90_GLOBAL, "ISURBAN", geo_em%isurban)
    call error_handler(ierr, "Problem nf90_put_att ISURBAN")
  
    ierr = nf90_put_att(ncid, NF90_GLOBAL, "ISICE", geo_em%isice)
    call error_handler(ierr, "Problem nf90_put_att ISICE")
  
  end if

!
! Even though the LDASIN files should work whichever landuse_datset
! is used at the HRLDAS step, it might be good to know which was
! used for making this dataset:
!
  ierr = nf90_put_att(ncid, NF90_GLOBAL, "MMINLU", geo_em%landuse_dataset)
  call error_handler(ierr, "Problem nf90_put_att MMINLU")

  ierr = nf90_enddef(ncid)
  call error_handler(ierr, "Problem exiting define mode")
end subroutine open_netcdf_for_output

!==============================================================================
!==============================================================================

subroutine output_timestring_to_netcdf(ncid, hdate)
  ! Write the date/time stamp as a variable to the NetCDF file.
  use netcdf
  use module_geo_em
  implicit none
  integer,                     intent(in) :: ncid
  character(len=*),            intent(in) :: hdate
  
  integer,          parameter                :: DateStrLen = 19
  character(len=1), dimension(DateStrLen, 1) :: output_hdate
  integer                                    :: dimid_datestrlen
  integer                                    :: dimid_time
  integer                                    :: varid
  integer                                    :: i
  integer                                    :: ierr

  output_hdate(:,1) = (/ "0","0","0","0","-","0","0","-","0","0","_","0","0",":","0","0",":","0","0" /)
  do i = 1, len(hdate)
     output_hdate(i,1) = hdate(i:i)
  enddo
  
  ierr = nf90_inq_dimid(ncid, "Time", dimid_time)
  call error_handler(ierr, "OUTPUT_TIMESTRING_TO_NETCDF: Problem finding dimension 'Time'")

  ierr = nf90_inq_dimid(ncid, "DateStrLen", dimid_datestrlen)
  call error_handler(ierr, "OUTPUT_TIMESTRING_TO_NETCDF: Problem finding dimension 'DateStrLen'")

  ierr = nf90_redef(ncid)
  call error_handler(ierr, "OUTPUT_TIMESTRING_TO_NETCDF: Problem NF90_REDEF")

  ierr = nf90_def_var(ncid,  "Times",  NF90_CHAR, (/dimid_datestrlen,dimid_Time/), varid)
  call error_handler(ierr, "OUTPUT_TIMESTRING_TO_NETCDF: Problem defining variable 'Times'")

  ierr = nf90_enddef(ncid)
  call error_handler(ierr, "OUTPUT_TIMESTRING_TO_NETCDF: Problem with enddef")

  ierr = nf90_put_var(ncid, varid, output_hdate, (/1,1/), (/datestrlen,1/))
  call error_handler(ierr, "OUTPUT_TIMESTRING_TO_NETCDF: Problem putting variable 'Time'")

end subroutine output_timestring_to_netcdf

!==============================================================================
!==============================================================================

subroutine output_to_netcdf(ncid, name, units, array, idim, jdim)
  use module_geo_em
  implicit none
  integer, intent(in) :: ncid
  character(len=*), intent(in) :: name
  character(len=*), intent(in) :: units
  integer, intent(in) :: idim, jdim
  real, dimension(idim,jdim), intent(in) :: array

  integer :: varid, ierr
  integer :: dimid_time, dimid_ix, dimid_jx

  ierr = nf90_inq_dimid(ncid, "Time", dimid_time)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'Time'")

  ierr = nf90_inq_dimid(ncid, "west_east", dimid_ix)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'west_east'")

  ierr = nf90_inq_dimid(ncid, "south_north", dimid_jx)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'south_north'")

  ierr = nf90_redef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem NF90_REDEF")

  ierr = nf90_def_var(ncid,  trim(name),  NF90_FLOAT, (/dimid_ix,dimid_jx,dimid_Time/), varid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem defining variable "//trim(name))

  ierr = nf90_put_att(ncid, varid, "units", trim(units))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting attribute units: "//trim(units))

  ! ierr = nf90_put_att(ncid, varid, "missing_value", -1.E36)
  ierr = nf90_put_att(ncid, varid, "_FillValue", -1.E36)

  ierr = nf90_enddef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem with enddef")

  ierr = nf90_put_var(ncid, varid, array, (/1,1,1/), (/idim,jdim,1/))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting variable "//trim(name))

end subroutine output_to_netcdf

subroutine output_to_netcdf_soil(ncid, name, units, array1, array2, array3, array4, idim, jdim, nsoil)
  use module_geo_em
  implicit none
  integer, intent(in) :: ncid
  character(len=*), intent(in) :: name
  character(len=*), intent(in) :: units
  integer, intent(in) :: idim, jdim, nsoil
  real, dimension(idim,jdim), intent(in) :: array1, array2, array3, array4
  
  real, dimension(idim,jdim,nsoil) :: array3d

  integer :: varid, ierr
  integer :: dimid_time, dimid_ix, dimid_jx, dimid_kx
  
  array3d(:,:,1) = array1
  array3d(:,:,2) = array2
  array3d(:,:,3) = array3
  array3d(:,:,4) = array4

  ierr = nf90_inq_dimid(ncid, "Time", dimid_time)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'Time'")

  ierr = nf90_inq_dimid(ncid, "west_east", dimid_ix)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'west_east'")

  ierr = nf90_inq_dimid(ncid, "south_north", dimid_jx)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'south_north'")

  ierr = nf90_inq_dimid(ncid, "soil_layers_stag", dimid_kx)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'soil_layers_stag'")

  ierr = nf90_redef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem NF90_REDEF")

  ierr = nf90_def_var(ncid,  trim(name),  NF90_FLOAT, (/dimid_ix,dimid_jx,dimid_kx,dimid_Time/), varid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem defining variable "//trim(name))

  ierr = nf90_put_att(ncid, varid, "units", trim(units))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting attribute units: "//trim(units))

  ! ierr = nf90_put_att(ncid, varid, "missing_value", -1.E36)
  ierr = nf90_put_att(ncid, varid, "_FillValue", -1.E36)

  ierr = nf90_enddef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem with enddef")

  ierr = nf90_put_var(ncid, varid, array3d, (/1,1,1,1/), (/idim,jdim,nsoil,1/))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting variable "//trim(name))

end subroutine output_to_netcdf_soil

subroutine output_to_netcdf_int(ncid, name, units, array, idim, jdim)
  use module_geo_em
  implicit none
  integer, intent(in) :: ncid
  character(len=*), intent(in) :: name
  character(len=*), intent(in) :: units
  integer, intent(in) :: idim, jdim
  integer, dimension(idim,jdim), intent(in) :: array

  integer :: varid, ierr
  integer :: dimid_time, dimid_ix, dimid_jx

  ierr = nf90_inq_dimid(ncid, "Time", dimid_time)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'Time'")

  ierr = nf90_inq_dimid(ncid, "west_east", dimid_ix)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'west_east'")

  ierr = nf90_inq_dimid(ncid, "south_north", dimid_jx)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'south_north'")

  ierr = nf90_redef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem NF90_REDEF")

  ierr = nf90_def_var(ncid,  trim(name),  NF90_INT, (/dimid_ix,dimid_jx,dimid_Time/), varid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem defining variable "//trim(name))

  ierr = nf90_put_att(ncid, varid, "units", trim(units))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting attribute units: "//trim(units))

  ! ierr = nf90_put_att(ncid, varid, "missing_value", -1.E36)
  ierr = nf90_put_att(ncid, varid, "_FillValue", -999999)

  ierr = nf90_enddef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem with enddef")

  ierr = nf90_put_var(ncid, varid, array, (/1,1,1/), (/idim,jdim,1/))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting variable "//trim(name))

end subroutine output_to_netcdf_int

subroutine output_to_netcdf_vector(ncid, name, units, nsoil, array)
  use module_geo_em
  implicit none
  integer, intent(in) :: ncid
  character(len=*), intent(in) :: name
  character(len=*), intent(in) :: units
  integer, intent(in) :: nsoil
  real, dimension(nsoil), intent(in) :: array

  integer :: varid, ierr
  integer :: dimid_time, dimid_kx

  ierr = nf90_inq_dimid(ncid, "Time", dimid_time)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'Time'")

  ierr = nf90_inq_dimid(ncid, "soil_layers_stag", dimid_kx)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem finding dimension 'soil_layers_stag'")

  ierr = nf90_redef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem NF90_REDEF")

  ierr = nf90_def_var(ncid,  trim(name),  NF90_FLOAT, (/dimid_kx,dimid_Time/), varid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem defining variable "//trim(name))

  ierr = nf90_put_att(ncid, varid, "units", trim(units))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting attribute units: "//trim(units))

  ierr = nf90_put_att(ncid, varid, "_FillValue", -1.e36)

  ierr = nf90_enddef(ncid)
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem with enddef")

  ierr = nf90_put_var(ncid, varid, array, (/1,1/), (/nsoil,1/))
  call error_handler(ierr, "OUTPUT_TO_NETCDF: Problem putting variable "//trim(name))

end subroutine output_to_netcdf_vector

!==============================================================================
!==============================================================================

subroutine fillsm(data, mask, nx, ny)
  use kwm_grid_utilities
  implicit none
  integer,                    intent(in)      :: nx
  integer,                    intent(in)      :: ny
  real,    dimension(nx, ny), intent(inout)   :: data
  logical, dimension(nx, ny), intent(in)      :: mask

  integer :: i, k
  real, dimension(nx,ny) :: hold

  hold = data

  do i = 1, 100
     call smt121(data, nx, ny, 5)
     where(mask)
        data = hold
     end where
  enddo

end subroutine fillsm

!==============================================================================
!==============================================================================

subroutine interp_rainfall_nearest_neighbor(datastruct, newarr, mix, mjx, geo_em)
  ! 
  ! Fill array <newarr> with rainfall data from <datastruct>
  !
  use module_input_data_structure
  use kwm_grid_utilities
  use module_geo_em
  implicit none
  type(input_data_type) :: datastruct
  type(geo_em_type), intent(in) :: geo_em
  integer, intent(in) :: mix, mjx
  real, dimension(mix,mjx) :: newarr

  integer :: ii, jj
  real    :: x, y
  integer :: xn, yn
  real    :: east_longitude

  newarr = 0.0

  !KWM where (datastruct%data < 0) datastruct%data = 0
  do ii = 1, mix
     do jj = 1, mjx
        ! Compute the x/y location in the <datastruct> dataset of the HRLDAS point (ii,jj).

        ! call datastruct_lltoxy(geo_em%lat(ii,jj), geo_em%lon(ii,jj), x, y, datastruct)

        call latlon_to_ij(datastruct%proj, geo_em%lat(ii,jj), geo_em%lon(ii,jj), x, y)

        xn = nint(x)
        yn = nint(y)
        if ((xn>0).and.(yn>0).and.(xn<=size(datastruct%data,1)).and.(yn<=size(datastruct%data,2))) then
           newarr(ii,jj) = datastruct%data(xn,yn)
           !KWM if (newarr(ii,jj) < 0) newarr(ii,jj) = 0
           if (newarr(ii,jj) < 0) newarr(ii,jj) = -1.E36
        else
           newarr(ii,jj) = -1.E36
        endif
     enddo
  enddo

end subroutine interp_rainfall_nearest_neighbor

!==============================================================================
!==============================================================================

subroutine interp_rainfall(datastruct, newarr, mix, mjx, geo_em)
  ! fill array newarr with rainfall data from datastruct
  use module_input_data_structure
!  use v3_module
  use kwm_grid_utilities
  use module_geo_em
  implicit none
  type(input_data_type) :: datastruct
  type(geo_em_type), intent(in) :: geo_em
  integer, intent(in) :: mix, mjx
  real, dimension(mix,mjx) :: newarr, fcount
  integer :: i, j
  real :: xlat, xlon, xx, yy
  real, parameter :: badval = -1.E30
  real :: factor
  integer :: ii, jj, iii, jjj
  real :: x, y, mx, my, x2, y2
  ! real, save, allocatable, dimension(:,:) :: mxa, mya
  real, allocatable, dimension(:,:) :: mxa, mya
  integer :: astat

!  integer, parameter :: nsub = 50
!  integer, parameter :: nsub = 15
!  integer, parameter :: nsub = 8
!  integer, parameter :: nsub = 4

  integer :: nsub

  ! Select nsub to have at least 10x10 source grid cells
  ! per destination grid cell.
  if(datastruct%proj%code == 0) then  ! Make a special exception for lat-lon: Barlage 20150311
    nsub = 10
  else
    nsub = ceiling(datastruct%proj%dx*1.E-3 * 10.0 / (geo_em%proj%dx*1.E-3))
  end if
  print*, 'nsub = ', nsub

  newarr = 0.0
  fcount = 0.0

  ! Take a more expensive approach, assigning portions of rainfall
  ! field's grid cells to various WRF grid cells as necessary.

  ! We recompute the mapping information every time, in case our source grid has changed.
     
  ILOOP : do i = 1, datastruct%nx
     JLOOP : do j = 1, datastruct%ny
        ! Compute (x,y) in WRF grid of point (gx,gy) in precip grid.
!KWM        call datastruct_xytoll(float(i), float(j), xlat, xlon, datastruct)
        call ij_to_latlon(datastruct%proj, float(i), float(j), xlat, xlon)
        call latlon_to_ij(geo_em%proj, xlat, xlon, x, y)
        ! Now X and Y are the x and y coordinates in the WRF 
        ! grid of the RAINFALL point i, j.

        if ((x > -2) .and. (y > -2) .and. (x < mix+2) .and. (y < mjx+2)) then

           do ii = 1, nsub
              x = float(i) + 0.5 * (1./float(nsub)-1) + float(ii-1)/float(nsub)
              do jj = 1, nsub
                 y = float(j) + 0.5 *(1./float(nsub)-1) + float(jj-1)/float(nsub)
!KWM                 call datastruct_xytoll(x, y, xlat, xlon, datastruct)
                 call ij_to_latlon(datastruct%proj,x, y, xlat, xlon)
                 call latlon_to_ij(geo_em%proj, xlat, xlon, x2, y2)

                 iii = nint(x2)
                 jjj = nint(y2)
                 if ((jjj > 0) .and. (iii > 0) .and. (jjj <= mjx) .and. (iii <= mix)) then
                    if (datastruct%data(i,j) > 0) then
                       newarr(iii,jjj) = newarr(iii,jjj) + datastruct%data(i,j)
                    endif
                    fcount(iii,jjj) = fcount(iii,jjj) + 1.0
                 endif
              enddo
           enddo

        endif
     enddo JLOOP
  enddo ILOOP

  where (fcount > 0.0)
     newarr = newarr / fcount
  elsewhere
     newarr = -1.E36
  end where

  where (newarr < 0)
!     newarr = 0.0 ! -1.E36
     newarr = -1.E36
  end where

end subroutine interp_rainfall

!==============================================================================
!==============================================================================

subroutine another_interp_rainfall(datastruct, newarr, mix, mjx, geo_em)
  !
  ! Fill array newarr with rainfall data from datastruct
  !
  ! Take an expensive approach, assigning portions of rainfall
  ! field's grid cells to various WRF grid cells as necessary.
  !
  use module_input_data_structure
  use kwm_grid_utilities
  use module_geo_em
  implicit none
  type(input_data_type) :: datastruct
  type(geo_em_type), intent(in) :: geo_em
  integer, intent(in) :: mix, mjx
  real, dimension(mix,mjx) :: newarr, fcount
  integer :: i, j
  real :: xlat, xlon, xx, yy
  real, parameter :: badval = -1.E30
  real :: factor
  integer :: ii, jj, iii, jjj
  real :: x, y, mx, my
  real, save, allocatable, dimension(:,:) :: mxa, mya
  integer :: astat

  ! For high-resolution cases, is this just going to exhaust our memory?
  real, save, allocatable, dimension(:,:,:,:) :: x2, y2

  integer :: nsub

  ! We need to check datastruct%iproj, datastruct%nx, datastruct%ny, datastruct%proj%lat1, datastruct%startlon
  ! datastruct%proj%latinc, datastruct%proj%loninc, datastruct%dx, datastruct%dy, datastruct%xlonc, datastruct%truelat1,
  ! and datastruct%truelat1 to be sure that our datastruct data is not from some different
  ! grid.

  logical :: samegrid
  integer, save :: iproj = -9999
  integer, save :: nx
  integer, save :: ny
  real,    save :: startlat
  real,    save :: startlon
  real,    save :: deltalat
  real,    save :: deltalon
  real,    save :: dx
  real,    save :: dy
  real,    save :: xlonc
  real,    save :: truelat1
  real,    save :: truelat2

  ! Check the grid info:
  samegrid = .TRUE.
  if (iproj    /= datastruct%proj%code)      samegrid=.FALSE.
  if (nx       /= datastruct%nx)             samegrid=.FALSE.
  if (ny       /= datastruct%ny)             samegrid=.FALSE.
  if (startlat /= datastruct%proj%lat1)      samegrid=.FALSE.
  if (startlon /= datastruct%proj%lon1)      samegrid=.FALSE.
  if (      dx /= datastruct%proj%dx)        samegrid=.FALSE.
  if (      dy /= datastruct%proj%dy)        samegrid=.FALSE.
  if (   xlonc /= datastruct%proj%stdlon)    samegrid=.FALSE.
  if (truelat1 /= datastruct%proj%truelat1)  samegrid=.FALSE.
  if (truelat2 /= datastruct%proj%truelat2)  samegrid=.FALSE.

  ! Select nsub to have at least 10x10 source grid cells
  ! per destination grid cell.
  ! nsub = ceiling(datastruct%proj%dx * 10.0 / (geo_em%proj%dx))
  nsub = ceiling(datastruct%proj%dx * 11.0 / geo_em%proj%dx)

  newarr = 0.0
  fcount = 0.0

  if (.not. samegrid) then
     write(*,'("Computing new grid information for rainfall remapping.")')
     print*, 'nsub = ', nsub
     if (allocated(mxa)) deallocate(mxa)
     if (allocated(mya)) deallocate(mya)
     if (allocated(x2))  deallocate(x2)
     if (allocated(y2))  deallocate(y2)
     ! Save this information:
     iproj    = datastruct%proj%code
     nx       = datastruct%nx
     ny       = datastruct%ny
     startlat = datastruct%proj%lat1
     startlon = datastruct%proj%lon1
     dx       = datastruct%proj%dx
     dy       = datastruct%proj%dy
     xlonc    = datastruct%proj%stdlon
     truelat1 = datastruct%proj%truelat1
     truelat2 = datastruct%proj%truelat2
  endif

  if (.not. allocated(mxa)) then
     allocate(mxa(datastruct%nx,datastruct%ny), stat=astat)
     if (astat /= 0) stop "Problem allocating MXA"
     allocate(mya(datastruct%nx,datastruct%ny), stat=astat)
     if (astat /= 0) stop "Problem allocating MYA"
     allocate(x2(datastruct%nx,datastruct%ny,nsub,nsub), stat=astat)
     if (astat /= 0) stop "Problem allocating X2"
     allocate(y2(datastruct%nx,datastruct%ny,nsub,nsub), stat=astat)
     if (astat /= 0) stop "Problem allocating Y2"
     ILOOP1 : do i = 1, datastruct%nx
        JLOOP1 : do j = 1, datastruct%ny
           ! Compute (x,y) in WRF grid of point (gx,gy) in precip grid.
           call ij_to_latlon(datastruct%proj, float(i), float(j), xlat, xlon)
           call latlon_to_ij(geo_em%proj, xlat, xlon, mxa(i,j), mya(i,j))

           ! Now MX and MY are the x and y coordinates in the WRF 
           ! grid of the RAINFALL point i, j.

        if ((mxa(i,j) > -2) .and. (mya(i,j) > -2) .and. (mxa(i,j) < mix+2) .and. (mya(i,j) < mjx+2)) then
           do ii = 1, nsub
              x = float(i) + 0.5 * (1./float(nsub)-1) + float(ii-1)/float(nsub)
              do jj = 1, nsub
                 y = float(j) + 0.5 *(1./float(nsub)-1) + float(jj-1)/float(nsub)
                 call ij_to_latlon(datastruct%proj, x, y, xlat, xlon)
                 call latlon_to_ij(geo_em%proj, xlat, xlon, x2(i,j,ii,jj), y2(i,j,ii,jj))
              enddo
           enddo

        endif

        enddo JLOOP1
     enddo ILOOP1
  endif

  ILOOP : do i = 1, datastruct%nx
     JLOOP : do j = 1, datastruct%ny
        ! Find the WRF coordinates of the DATASTRUCT point in question
        if ((mxa(i,j) > -2) .and. (mya(i,j) > -2) .and. (mxa(i,j) < mix+2) .and. (mya(i,j) < mjx+2)) then

           do ii = 1, nsub
              do jj = 1, nsub
                 iii = nint(x2(i,j,ii,jj))
                 jjj = nint(y2(i,j,ii,jj))
                 if ((jjj > 0) .and. (iii > 0) .and. (jjj <= mjx) .and. (iii <= mix)) then
                    ! if (datastruct%data(i,j) >0) then
                    if (datastruct%data(i,j) >=0) then
                       newarr(iii,jjj) = newarr(iii,jjj) + datastruct%data(i,j)
                    endif
                    fcount(iii,jjj) = fcount(iii,jjj) + 1.0
                 endif
              enddo
           enddo
        endif
     enddo JLOOP
  enddo ILOOP

  where (fcount > 0.0)
     newarr = newarr / fcount
  elsewhere
     newarr = -1.E36
  end where

  where (newarr < 0)
!     newarr = 0.0 ! -1.E36
     newarr = -1.E36
  end where

end subroutine another_interp_rainfall

!==============================================================================
!==============================================================================

subroutine rescale_sw_time_offset(datastruct)
  use module_input_data_structure
  use kwm_date_utilities
  implicit none
  type(input_data_type), intent(inout) :: datastruct

  integer :: idim
  integer :: jdim

!KWM  real, parameter :: pi = 3.14159265

  character(len=16) :: nowdate
  integer :: jday
  integer :: ihour
  integer :: iminute

  integer :: i, j
  real    :: lat, lon
  real    :: latrad, lonrad

  real :: gg
  real :: declin
  real :: tc
  real :: SHA
  real :: hour
  real :: time_of_day
  real :: time_of_day00
  real :: cza
  real :: cza00

  idim = datastruct%nx
  jdim = datastruct%ny

  ! Get the hour and minute from the date string.
  read(datastruct%hdate(12:16), '(I2,1x,I2)') ihour, iminute
  if (iminute == 0) return ! No adjusting of SW data necessary

  ! Find the julian day from the date string.
  call geth_idts(datastruct%hdate(1:10), datastruct%hdate(1:4)//"-01-01", jday)
  jday = jday + 1

  ! The (GMT) time of day as encoded in the data, hours and fractional minutes.
  time_of_day = float(ihour) + float(iminute)/60.

  ! The (GMT) time of day, truncated to the hour.
  time_of_day00 = float(ihour)

  write(*, '(12x,"SW offset:  Record time:", F6.3, ";  HRLDAS analysis time:", F6.3, ";   Time offset (hours):",  F6.4)') &
       time_of_day, time_of_day00, time_of_day - time_of_day00

  do i = 1, idim
     do j = 1, jdim

        ! First, compute the lat/lon at the DATASTRUCT points.
!KWM        call datastruct_xytoll(float(i), float(j), lat, lon, datastruct)
        call ij_to_latlon(datastruct%proj, float(i), float(j), lat, lon)
        latrad = lat*pi/180.
        lonrad = lon*pi/180.

        call get_declin(jday, time_of_day, latrad, lonrad, declin, sha)

        ! CZA -- Cosine of the solar zenith angle
        cza = sin(latrad)*sin(DECLIN)+cos(latrad)*cos(DECLIN)*cos(SHA)
        if (cza < 0.1) cza = 0;

        call get_declin(jday, time_of_day00, latrad, lonrad, declin, sha)
        cza00 = sin(latrad)*sin(DECLIN)+cos(latrad)*cos(DECLIN)*cos(SHA)
        if (cza00 < 0) cza00 = 0;

        if (datastruct%data(i,j) > 0) then
           if (cza < 0.05) then
              datastruct%data(i,j) = 0.
           else
              datastruct%data(i,j) = cza00/cza * datastruct%data(i,j)
           endif
        endif
     enddo
  enddo

end subroutine rescale_sw_time_offset

!==============================================================================
!==============================================================================

subroutine get_declin(jday, gmthour, latrad, lonrad, declin, sha)
  implicit none
  integer, intent(in) :: jday
  real, intent(in) :: gmthour
  real, intent(in) :: latrad
  real, intent(in) :: lonrad
  real, intent(out) :: declin
  real, intent(out) :: sha
  ! real, intent(out) :: sza

  real :: gg, tc
  real, parameter :: pi = 3.14159265

  ! Fractional day of the year, in radians
  gg = (360./365.25) * (JDAY+gmthour/24.) * pi/180.

  ! Solar declination angle, in radians.
  DECLIN = 0.006918 - 0.399912*cos(gg) + 0.070257*sin(gg) - 0.006758*cos(2.0*gg) + &
       0.000907*sin(2.0*gg) - 0.002697*cos(3.0*gg) + 0.00148*sin(3.0*gg)

  ! Time Correction for solar angle, in radians.  Whatever.
  TC = 0.000075 + 0.001868*cos(gg) - 0.032077*sin(gg) - 0.014615*cos(2.0*gg) - &
       0.040849*sin(2.0*gg)

  ! Solar Hour Angle, in radians
  SHA = ((gmthour-12.0)*15.0)*(pi/180.) + lonrad + TC
  ! SHA = (gmthour*15.0)*(pi/180.) + lonrad + TC

  ! ! Solar Zenith Angle, in radians
  ! SZA = acos(sin(latrad)*sin(DECLIN)+cos(latrad)*cos(DECLIN)*cos(SHA))

  !  ! Solar Elevation Angle, in radians.
  !  SEA = (pi/2.)-SZA

  !  ! Azimuth Angle
  !  AZ = acos((sin(DECLIN)-sin(latrad)*cos(SZA))/(cos(Latrad)*sin(SZA)))

end subroutine get_declin

!==============================================================================
!==============================================================================

subroutine nighttime_SW(hdate, field, idim, jdim, geo_em)
  ! IDIM and JDIM are the dimensions of FIELD, which should also be the same 
  ! as the geo_em%IDIM and geo_em%JDIM dimensions.
  use module_geo_em
  use kwm_date_utilities
  use kwm_grid_utilities
  implicit none
  character(len=*), intent(in) :: hdate
  integer, intent(in) :: idim, jdim
  type (geo_em_type), intent(in) :: geo_em
  real, dimension(idim,jdim), intent(inout) :: field

  integer :: i, j, jday, ihour, iminute
  real :: lat, lon, latrad, lonrad, gmthour
  real :: declin, sha, cosza
  real, dimension(idim, jdim) :: maskarray
  real, dimension(idim, jdim) :: mask2

  integer :: ii, jj, mcount, iiterm
  integer :: cdist
  integer :: iimin, iimax, jjmin, jjmax
  integer, allocatable, dimension(:,:) :: mtx

  call geth_idts(hdate(1:10), hdate(1:4)//"-01-01", jday)
  jday = jday + 1
  read(hdate(12:16), '(I2,1x,I2)') ihour, iminute
  gmthour = float(ihour) + float(iminute)/60.

  ! Make a mask array
  do i = 1, idim
     do j = 1, jdim
        latrad = geo_em%lat(i,j) * rad_per_deg
        lonrad = geo_em%lon(i,j) * rad_per_deg
        call get_declin(jday, gmthour, latrad, lonrad, declin, sha)

        cosza = sin(latrad)*sin(DECLIN)+cos(latrad)*cos(DECLIN)*cos(SHA)

        if (cosza > 0.0) then
           maskarray(i,j) = 1.0
        else
           maskarray(i,j) = 0.0
        endif
     enddo
  enddo

  ! Smooth the mask array a bit, to get us a less abrupt change
  !        Took this out on 14 Feb 2008.  Kind of a hack.
  ! call smt121(maskarray, idim, jdim, 10)

  field = field * maskarray

end subroutine nighttime_SW

!==============================================================================
!==============================================================================

subroutine close_flnm(flnm)
  implicit none
  character(len=*), intent(in) :: flnm
  integer :: n
  inquire(file=trim(flnm), number=n)
  if (n > -1) close(n)
end subroutine close_flnm

!==============================================================================
!==============================================================================

