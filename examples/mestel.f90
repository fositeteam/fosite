!#############################################################################
!#                                                                           #
!# fosite - 3D hydrodynamical simulation program                             #
!# module: mestel.f03                                                        #
!#                                                                           #
!# Copyright (C) 2012-2018                                                   #
!# Manuel Jung    <mjung@astrophysik.uni-kiel.de>                            #
!# Björn Sperling <sperling@astrophysik.uni-kiel.de>                         #
!# Tobias Illenseer <tillense@astrophysik.uni-kiel.de>                       #
!#                                                                           #
!# This program is free software; you can redistribute it and/or modify      #
!# it under the terms of the GNU General Public License as published by      #
!# the Free Software Foundation; either version 2 of the License, or (at     #
!# your option) any later version.                                           #
!#                                                                           #
!# This program is distributed in the hope that it will be useful, but       #
!# WITHOUT ANY WARRANTY; without even the implied warranty of                #
!# MERCHANTABILITY OR FITNESS FOR A PARTICULAR PURPOSE, GOOD TITLE or        #
!# NON INFRINGEMENT.  See the GNU General Public License for more            #
!# details.                                                                  #
!#                                                                           #
!# You should have received a copy of the GNU General Public License         #
!# along with this program; if not, write to the Free Software               #
!# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.                 #
!#                                                                           #
!#############################################################################

!----------------------------------------------------------------------------!
!> self-gravitating accretion disk
!!
!! \author Manuel Jung
!! \author Björn Sperling
!! \author Tobias Illenseer
!!
!! 2D simulation of a geometrically thin, self-gravitating accretion disk
!! around a supermassive black hole in polar geometry with logarithmic
!! radial spacing. The standard setup solves the non-isothermal inviscid
!! Euler equations with thin-disk gray cooling (see \link sources_diskcooling \endlink ).
!! Gravitational forces account for the central point mass as well as self-gravity
!! of the disk.
!!
!! The setup is based on those described in \cite britsch2006 .
!!
!! <div class="row"> <div class="col-md-6">
!!  Simulation parameters         | \f$ \quad \f$
!!  ------------------            | -----------------
!!  black hole mass               | \f$ 10^7\, \mathsf{M}_\odot \f$
!!  disk / black hole mass ratio  | \f$ 0.1 \f$
!!  mean molecular weight         | \f$ 6.02\cdot 10^{-4}\, \mathsf{kg/mol} \f$
!!  specific heat ratio           | \f$ 1.4 \f$
!!  inner radius                  | \f$ 0.05\, \mathsf{pc} \f$
!!  outer radius                  | \f$ 1\, \mathsf{pc} \f$
!!
!!  Initial condition                              | \f$ \quad \f$
!!  ------------------                             | -----------------
!!  power law surface density, i. e. Mestel's disk | \f$ \Sigma \propto 1/r + \mathsf{noise} \f$
!!  constant temperature                           | \f$ 100\, \mathsf{K} \f$
!!  centrifugal balance                            | \f$ v_\varphi^2 = -r \partial_r \Phi \f$
!!
!! </div> <div class="col-md-6">
!! \image html http://www.astrophysik.uni-kiel.de/fosite/sgagndisk_mbh1e7_md1e6_0960.png "column density"
!! You can find a [time-lapse movie] (agndisk.html) showing the temporal evolution of the
!! column density in the [gallery] (gallery.html).
!! </div> </div>
!!
!! References:
!! - \cite britsch2006 M. Britsch, "Gravitational instability and fragmentation of self-gravitating accretion disks",
!!      PhD thesis, 2006
!!
!! \example markward.f90
!----------------------------------------------------------------------------!
PROGRAM mestel
  USE fosite_mod
#ifdef PARALLEL
#ifdef HAVE_MPI_MOD
  USE mpi
#endif
#endif
  IMPLICIT NONE
#ifdef PARALLEL
#ifdef HAVE_MPIF_H
  include 'mpif.h'
#endif
#endif
  !--------------------------------------------------------------------------!
  ! general constants
  REAL, PARAMETER :: GN = 6.67384E-11       ! Newtons grav. constant [m^3/kg/s^2]
  REAL, PARAMETER :: YEAR = 3.15576E+7      ! year [s]
  REAL, PARAMETER :: PARSEC = 3.0857E+16    ! parsec [m]
  REAL, PARAMETER :: AU = 1.49598E+11       ! astronomical unit [m]
  REAL, PARAMETER :: MSUN = 1.989E+30       ! solar mass [kg]
  REAL, PARAMETER :: RG = 8.31              ! gas constant
  ! simulation parameters
  REAL, PARAMETER :: SIMTIME = 1.0E+4*YEAR  ! simulation time [s]
  REAL, PARAMETER :: MBH = 1.0E+7*MSUN      ! initial black hole mass [kg]
  REAL, PARAMETER :: MRATIO = 0.1           ! initial mdisk/mbh mass ratio
  REAL, PARAMETER :: MDISK = MRATIO*MBH     ! initial disk mass [kg]
  REAL, PARAMETER :: TEMP = 100.0           ! initial temperature [K]
  REAL, PARAMETER :: NOISE = 0.3            ! initial noise level
  ! physics settings
  INTEGER, PARAMETER :: PHYS = EULER        ! transport model
  REAL, PARAMETER :: MU = 6.02E-4           ! mean molecular weight [kg/mol]
  REAL, PARAMETER :: GAMMA = 1.4            ! ratio of specific heats
  REAL, PARAMETER :: BETA_VIS = 1.0E-3      ! beta viscosity parameter
  ! mesh settings
  REAL, PARAMETER :: RMIN = 5.0E-2 * PARSEC ! inner radius [m]
  REAL, PARAMETER :: RMAX = 1.E+0 * PARSEC  ! outer radius [m]
  REAL, PARAMETER :: RGEO = 1.0 * PARSEC    ! geometry scaling constant
  INTEGER, PARAMETER :: MGEO = LOGCYLINDRICAL ! mesh geometry
  INTEGER, PARAMETER :: XRES = 32          ! mesh resolution (radial)
  INTEGER, PARAMETER :: YRES = 64          ! mesh resolution (azimuthal)
  INTEGER, PARAMETER :: ZRES = 1            ! mesh resolution (z)
  ! output settings
  INTEGER, PARAMETER :: ONUM = 1000         ! number of output time steps
  CHARACTER(LEN=256), PARAMETER :: &
  OFNAME = 'markward', &                    ! data file name
  ODIR   = "./"                             ! output directory
  !--------------------------------------------------------------------------!
  CLASS(fosite), ALLOCATABLE :: Sim
  !--------------------------------------------------------------------------!

ALLOCATE(Sim)
CALL Sim%InitFosite()
CALL MakeConfig(Sim%config)
CALL Sim%Setup()
CALL InitData(Sim%Timedisc,Sim%Mesh,Sim%Physics,Sim%Fluxes,Sim%Sources, &
              Sim%Timedisc%pvar%data4d,Sim%Timedisc%cvar%data4d)
CALL Sim%Run()
CALL Sim%Finalize()
DEALLOCATE(Sim)

CONTAINS
  SUBROUTINE MakeConfig(config)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    TYPE(Dict_TYP),POINTER :: config
    !------------------------------------------------------------------------!
    ! Local variable declaration
    TYPE(Dict_TYP),POINTER :: mesh,boundary,timedisc,datafile,&
                              sources,fluxes,grav,physics,rotframe,&
                              vis,cooling
    !------------------------------------------------------------------------!
    physics => Dict( &
        "problem"         / PHYS, &
        "output/bccsound" / 1, &
        "mu"              / MU, &
        "gamma"           / GAMMA, &
        "units"           / SI)

    fluxes => Dict( &
        "fluxtype"        / KT, &
        "order"           / LINEAR, &
        "variables"       / PRIMITIVE, &
        "limiter"         / VANLEER, &
        "theta"           / 1.2)

    mesh => Dict( &
        "meshtype"        / MIDPOINT, &
        "geometry"        / MGEO, &
        "inum"            / XRES, &
        "jnum"            / YRES, &
        "knum"            / ZRES, &
        "xmin"            / LOG(RMIN/PARSEC), &
        "xmax"            / LOG(RMAX/PARSEC), &
        "ymin"            / (-PI), &
        "ymax"            / ( PI), &
        "zmin"            / 0.0, &
        "zmax"            / 0.0, &
        "gparam"          / RGEO, &
        "decomposition"   / (/-1,1/), &
        "output/volume"   / 1 )

    boundary => Dict( &
        "western"         / CUSTOM, &
        "eastern"         / CUSTOM, &
        "southern"        / PERIODIC, &
        "northern"        / PERIODIC, &
        "bottomer"        / REFLECTING, &
        "topper"          / REFLECTING)

    grav => Dict( &
        "stype"           / GRAVITY, &
        "cvis"            / 0.9, &
        "output/height"   / 1, &
        "self/gtype"      / SPECTRAL, &
        "self/green"      / 1, &
        "pmass/gtype"     / POINTMASS, &
        "pmass/potential" / NEWTON, &
        "pmass/mass"      / MBH, &
        "pmass/outbound"  / 1)

    ! cooling model
    cooling => Dict( &
        "stype"           / DISK_COOLING, &
        "method"          / GRAY, &
!        "method"          / GAMMIE, &
        "b_cool"          / 10.0, &
        "Tmin"            / 30.0, &
        "rhomin"          / 1.0E-30, &
        "cvis"            / 0.01)

    ! viscosity model
    vis => Dict( &
        "stype"           / VISCOSITY, &
        "vismodel"        / BETA, &
        "dynconst"        / BETA_VIS, &
        "output/stress"   / 1, &
        "output/dynvis"   / 1, &
        "output/kinvis"   / 1, &
        "cvis"            / 0.5)

    ! collect source terms
    sources => Dict( &
        "grav"            / grav, &
!        "viscosity"       / vis, &
        "diskcooling"     / cooling)

    ! time discretization settings
    timedisc => Dict( &
        "method"          / SSPRK, &
!        "fargo"           / 0, &
!        "rhstype"         / 1, &
        "tol_rel"         / 1.0E-2, &
        "cfl"             / 0.3, &
        "stoptime"        / SIMTIME, &
        "dtlimit"         / 1.0E+2, &
        "maxiter"         / 2000000000)

    ! add absolute error bounds and output fields depending on physics
    SELECT CASE(PHYS)
    CASE(EULER)
       CALL SetAttr(timedisc, "tol_abs", (/1.0E-5, 1.0E-3, 0.0, 1.0E+6/))
       CALL SetAttr(timedisc, "output/xmomentum", 0)
       CALL SetAttr(timedisc, "output/ymomentum", 0)
       CALL SetAttr(timedisc, "output/energy", 0)
       CALL SetAttr(timedisc, "output/rhs", 0)
       CALL SetAttr(timedisc, "output/external_sources", 0)
    CASE DEFAULT
       CALL Error(Sim,"MakeConfig","Physics model not supported.")
    END SELECT

    ! data file settings
    datafile => Dict( &
        "fileformat"      / VTK, &
        "filename"        / "mestel", &
        "count"           / ONUM)

    ! create configuration
    config => Dict( &
        "physics"         / physics, &
        "fluxes"          / fluxes, &
        "mesh"            / mesh, &
        "boundary"        / boundary, &
        "sources"         / sources, &
        "timedisc"        / timedisc, &
        "datafile"        / datafile)

  END SUBROUTINE MakeConfig


  SUBROUTINE InitData(Timedisc,Mesh,Physics,Fluxes,Sources,pvar,cvar)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(timedisc_base), INTENT(INOUT) :: Timedisc
    CLASS(mesh_base),     INTENT(IN)    :: Mesh
    CLASS(physics_base),  INTENT(INOUT) :: Physics
    CLASS(fluxes_base),   INTENT(INOUT) :: Fluxes
    CLASS(sources_base),  POINTER       :: Sources
    REAL, DIMENSION(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX,Physics%VNUM), &
                          INTENT(OUT)   :: pvar,cvar
    !------------------------------------------------------------------------!
    ! Local variable declaration
    CLASS(sources_base), POINTER :: sp
    CLASS(sources_gravity), POINTER :: gp
    INTEGER :: i,j,k
#ifdef PARALLEL
    INTEGER :: ierror
#endif
    REAL    :: mass,ephi(2),cs,vphi
    REAL, DIMENSION(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX) &
            :: rands
    REAL, DIMENSION(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX,3) &
            :: accel
    REAL, DIMENSION(:,:,:),   POINTER :: r,Sigma
    REAL, DIMENSION(:,:,:,:), POINTER :: r_vec
    CHARACTER(LEN=20) :: mdisk_str
    !------------------------------------------------------------------------!
    ! distance from origin to cell bary centers and position vector
    r => Mesh%RemapBounds(Mesh%radius%bcenter(:,:,:))
    r_vec => Mesh%RemapBounds(Mesh%posvec%bcenter(:,:,:,:))
    ! pointer to density array
    Sigma => Mesh%RemapBounds(pvar(:,:,:,Physics%DENSITY))

    ! set surface density using radial power law (1/r) with a little noise
    CALL InitRandSeed(Timedisc)
    CALL RANDOM_NUMBER(rands)
    rands = rands * NOISE * 2.0 + (1.0 - NOISE)
    Sigma = rands*(RMIN/r(:,:,:))

    ! determine disk mass
    mass = SUM(Mesh%volume(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX) * &
                     Sigma(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
#ifdef PARALLEL
       CALL MPI_AllReduce(MPI_IN_PLACE,mass,1,DEFAULT_MPI_REAL,MPI_SUM, &
            Mesh%comm_cart,ierror)
#endif
    ! rescale disk mass
    Sigma(:,:,:) = Sigma(:,:,:) * MDISK / mass

    ! set pressure using surface density and initial temperature
    pvar(:,:,:,Physics%PRESSURE) = Physics%constants%RG/Physics%MU * TEMP * Sigma(:,:,:)

    ! reset velocities
    pvar(:,:,:,Physics%XVELOCITY:Physics%YVELOCITY) = 0.0

    CALL Physics%Convert2Conservative(Mesh,pvar,cvar)


    ! 2. azimuthal velocity: balance initial radial acceleration with centrifugal acceleration
    ! get gravitational acceleration
    sp => Sources
    DO
      IF (ASSOCIATED(sp).EQV..FALSE.) RETURN
      SELECT TYPE(sp)
      CLASS IS(sources_gravity)
        gp => sp
        EXIT
      END SELECT
      sp => sp%next
    END DO

    IF (ASSOCIATED(sp)) THEN
       CALL gp%UpdateGravity(Mesh,Physics,Fluxes,pvar,0.0,0.0)
    ELSE
       CALL Sim%Error("InitData","no gravity term initialized")
    END IF

    ! set the velocity due to the centrifugal force
    pvar(:,:,:,Physics%XVELOCITY:Physics%XVELOCITY+Physics%VDIM-1) = &
          Timedisc%GetCentrifugalVelocity(Mesh,Physics,Fluxes,Sources,(/0.,0.,1./),gp%accel)

    ! setting for custom boundary conditions (western boundary)
    IF(Timedisc%Boundary%boundary(WEST)%p%GetType().EQ.CUSTOM) THEN
      Timedisc%Boundary%boundary(WEST)%p%cbtype(:,:,Physics%DENSITY)   = CUSTOM_LOGEXPOL
      Timedisc%Boundary%boundary(WEST)%p%cbtype(:,:,Physics%XVELOCITY) = CUSTOM_OUTFLOW
      Timedisc%Boundary%boundary(WEST)%p%cbtype(:,:,Physics%YVELOCITY) = CUSTOM_KEPLER
      Timedisc%Boundary%boundary(WEST)%p%cbtype(:,:,Physics%PRESSURE)  = CUSTOM_LOGEXPOL
    END IF

    ! setting for custom boundary conditions (eastern boundary)
    IF(Timedisc%Boundary%boundary(EAST)%p%GetType().EQ.CUSTOM) THEN
      Timedisc%Boundary%boundary(EAST)%p%cbtype(:,:,Physics%DENSITY)   = CUSTOM_REFLECT
      Timedisc%Boundary%boundary(EAST)%p%cbtype(:,:,Physics%XVELOCITY) = CUSTOM_REFLECT
      Timedisc%Boundary%boundary(EAST)%p%cbtype(:,:,Physics%YVELOCITY) = CUSTOM_LOGEXPOL
      Timedisc%Boundary%boundary(EAST)%p%cbtype(:,:,Physics%PRESSURE)  = CUSTOM_REFLECT
    END IF

    CALL Physics%Convert2Conservative(Mesh,pvar,cvar)
    ! print some information
    WRITE (mdisk_str, '(ES8.2)') mdisk/MSUN
    CALL Mesh%Info(" DATA-----> initial condition: Mestel's disk")
    CALL Mesh%Info("            disk mass:         " // TRIM(mdisk_str) // " M_sun")

  END SUBROUTINE InitData

  SUBROUTINE InitRandSeed(Timedisc)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(timedisc_base), INTENT(IN) :: Timedisc
    INTEGER :: i, n, clock
    INTEGER, DIMENSION(:), ALLOCATABLE :: seed
    !------------------------------------------------------------------------!
    ! Initialize random number generator with a seed based on the systems time
    ! source: http://gcc.gnu.org/onlinedocs/gfortran/RANDOM_005fSEED.html
    CALL RANDOM_SEED(size = n)
    ALLOCATE(seed(n))
    CALL SYSTEM_CLOCK(COUNT=clock)
    seed = clock + 37 * (/ (i - 1, i = 1, n) /)
#ifdef PARALLEL
    seed = seed + GetRank(Timedisc)
#endif
    CALL RANDOM_SEED(PUT = seed)
    DEALLOCATE(seed)
  END SUBROUTINE InitRandSeed
END PROGRAM mestel