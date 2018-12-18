!#############################################################################
!#                                                                           #
!# fosite - 3D hydrodynamical simulation program                             #
!# module: boundary_custom.f03                                               #
!#                                                                           #
!# Copyright (C) 2006-2018                                                   #
!# Tobias Illenseer <tillense@astrophysik.uni-kiel.de>                       #
!# Jannes Klee      <jklee@astrophysik.uni-kiel.de>                          #
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
!> \author Tobias Illenseer
!! \author Jannes Klee
!!
!! \brief Boundary module for custom conditions
!!
!! \attention Not well tested, use with care, since the transition to
!!            Fosite 3D. Use with care.
!----------------------------------------------------------------------------!
MODULE boundary_custom_mod
  USE boundary_base_mod
  USE boundary_fixed_mod
  USE mesh_base_mod
  USE physics_base_mod
  USE common_dict
  IMPLICIT NONE
  !--------------------------------------------------------------------------!
  PRIVATE
  TYPE, EXTENDS(boundary_fixed) :: boundary_custom
    INTEGER, DIMENSION(:),  ALLOCATABLE :: cbtype    !< custom boundary condition type
    REAL, DIMENSION(:,:,:), ALLOCATABLE :: Rscale, & !< radial scaling constants
                                        invRscale    !< inverse radial scaling constants
    REAL, DIMENSION(:,:,:), POINTER     :: radius    !< distance to center of mass for Kepler conditions
  CONTAINS
    PROCEDURE :: InitBoundary_custom
    PROCEDURE :: Finalize
    PROCEDURE :: SetBoundaryData
    PROCEDURE :: SetCustomBoundaries
  END TYPE
  CHARACTER(LEN=32), PARAMETER  :: boundcond_name = "custom"
  !--------------------------------------------------------------------------!
  ! create bit masks for custom boundary conditions
  ENUM, BIND(C)
    ENUMERATOR :: CUSTOM_UNDEFINED = 0, &
                  CUSTOM_NOGRAD    = 1, &  ! no gradients (default)
                  CUSTOM_PERIOD    = 2, &  ! periodic
                  CUSTOM_REFLECT   = 3, &  ! reflecting
                  CUSTOM_REFLNEG   = 4, &  ! reflect and change sign
                  CUSTOM_EXTRAPOL  = 5, &  ! linear extrapolation
                  CUSTOM_FIXED     = 6, &  ! set fixed boundary data
                  CUSTOM_LOGEXPOL  = 7, &  ! extrapolation of log values
                  CUSTOM_OUTFLOW   = 8, &  ! nograd/reflect depending on flow direction
                  CUSTOM_KEPLER    = 9, &  ! extrapolate according to Keplers law
                  CUSTOM_ANGKEPLER = 10    ! same but for angular momentum instead of
  END ENUM
  !--------------------------------------------------------------------------!
  PUBLIC :: &
       boundary_custom, &
       ! constants
       CUSTOM_NOGRAD, CUSTOM_PERIOD, CUSTOM_REFLECT, CUSTOM_REFLNEG, &
       CUSTOM_EXTRAPOL, CUSTOM_FIXED, CUSTOM_LOGEXPOL, &
       CUSTOM_OUTFLOW, CUSTOM_KEPLER, CUSTOM_ANGKEPLER
  !--------------------------------------------------------------------------!

CONTAINS

  !> \public Constructor for custom boundary conditions
  SUBROUTINE InitBoundary_custom(this,Mesh,Physics,dir,config)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(boundary_custom), INTENT(INOUT) :: this
    CLASS(mesh_base),     INTENT(IN)    :: Mesh
    CLASS(physics_base),  INTENT(IN)    :: Physics
    TYPE(Dict_TYP),       POINTER       :: config
    INTEGER,              INTENT(IN)    :: dir
    !------------------------------------------------------------------------!
    INTEGER            :: err = 0
    !------------------------------------------------------------------------!
    CALL this%InitBoundary(Mesh,Physics,CUSTOM,boundcond_name,dir,config)

    ! allocate memory for boundary data and mask
    ALLOCATE(this%cbtype(Physics%VNUM),STAT=err)
    IF (err.NE.0) &
       CALL this%Error("InitBoundary_custom", "Unable to allocate memory.")
    ! this array contains the boundary condition for each primitive variable;
    ! the user must call SetCustomBoundaries() after initialization to specifiy
    ! the actual boundary condition for each variable and supply user defined
    ! data arrays if necessary
    this%cbtype(:) = CUSTOM_UNDEFINED
  END SUBROUTINE InitBoundary_custom


  !> \public Applies the custom boundary conditions
  SUBROUTINE SetBoundaryData(this,Mesh,Physics,time,pvar)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(boundary_custom), INTENT(INOUT) :: this
    CLASS(mesh_base),     INTENT(IN)    :: Mesh
    CLASS(physics_base),  INTENT(IN)    :: Physics
    REAL,                 INTENT(IN)    :: time
    REAL, DIMENSION(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,MESH%KGMIN:Mesh%KGMAX,Physics%VNUM), &
                          INTENT(INOUT) :: pvar
    !------------------------------------------------------------------------!
    INTEGER       :: i,j,k,m
    !------------------------------------------------------------------------!
    SELECT CASE(this%GetDirection())
    CASE(WEST)
      DO m=1,Physics%VNUM
        SELECT CASE(this%cbtype(m))
        CASE(CUSTOM_NOGRAD)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_PERIOD)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMAX-i+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLECT)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN+i-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLNEG)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN+i-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_EXTRAPOL)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = (i+1)*pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              - i*pvar(Mesh%IMIN+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_FIXED)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = this%data(i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_LOGEXPOL)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              * ABS(pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              / pvar(Mesh%IMIN+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m))**i
          END DO
        CASE(CUSTOM_OUTFLOW)
! REMARK: this would work for any GINUM, but with lower performance
! !NEC$ SHORTLOOP
!           DO i=1,Mesh%GINUM
!             WHERE (pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m).GE.0.0 )
!               pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
!                 = -pvar(Mesh%IMIN+i-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
!             ELSEWHERE
!               pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
!                 = pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
!             END WHERE
!           END DO
          WHERE (pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m).GE.0.0 )
            pvar(Mesh%IGMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IGMIN+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          ELSEWHERE
            pvar(Mesh%IGMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IGMIN+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END WHERE
        CASE(CUSTOM_KEPLER)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = (pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              + this%radius(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA) &
              * this%invRscale(i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX) &
              - this%radius(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA
          END DO
        CASE(CUSTOM_ANGKEPLER)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = (pvar(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              + this%radius(Mesh%IMIN,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA) &
              * this%Rscale(i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX) &
              - this%radius(Mesh%IMIN-i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA
          END DO
        CASE DEFAULT
          CALL this%Error("boundary_custom::SetBoundaryData","western boundary: undefined conditions")
        END SELECT
      END DO
    CASE(EAST)
      DO m=1,Physics%VNUM
        SELECT CASE(this%cbtype(m))
        CASE(CUSTOM_NOGRAD)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
             = pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_PERIOD)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN+i-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLECT)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMAX-i+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLNEG)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMAX-i+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_EXTRAPOL)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = (i+1)*pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              - i*pvar(Mesh%IMAX-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_FIXED)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
             = this%data(i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_LOGEXPOL)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              * ABS(pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              / pvar(Mesh%IMAX-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m))**i
          END DO
        CASE(CUSTOM_OUTFLOW)
! REMARK: this would work for any GINUM, but with lower performance
! !NEC$ SHORTLOOP
!           DO i=1,Mesh%GINUM
!             WHERE (pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m).LE.0.0 )
!               pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
!                 = -pvar(Mesh%IMAX-i+1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
!             ELSEWHERE
!               pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
!                 = pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
!             END WHERE
!           END DO
          WHERE (pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m).LE.0.0 )
            pvar(Mesh%IGMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMAX-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IGMAX-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          ELSEWHERE
            pvar(Mesh%IGMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IGMAX-1,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END WHERE
        CASE(CUSTOM_KEPLER)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = (pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              + this%radius(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA)&
              * this%invRscale(i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX) &
              - this%radius(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA
          END DO
        CASE(CUSTOM_ANGKEPLER)
!NEC$ SHORTLOOP
          DO i=1,Mesh%GINUM
            pvar(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = (pvar(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              + this%radius(Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA)&
              * this%Rscale(i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX) &
              - this%radius(Mesh%IMAX+i,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA
          END DO
        CASE DEFAULT
          CALL this%Error("boundary_custom::SetBoundaryData","eastern boundary: undefined conditions")
        END SELECT
      END DO
    CASE(SOUTH)
      DO m=1,Physics%VNUM
        SELECT CASE(this%cbtype(m))
        CASE(CUSTOM_NOGRAD)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              =  pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_PERIOD)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-j+1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLECT)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+j-1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLNEG)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+j-1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_EXTRAPOL)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              = (j+1)*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m) &
              - j*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_FIXED)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              = this%data(Mesh%IMIN:Mesh%IMAX,j,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_LOGEXPOL)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m) &
              * ABS(pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m) &
              / pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+1,Mesh%KMIN:Mesh%KMAX,m))**j
          END DO
        CASE(CUSTOM_OUTFLOW)
! REMARK: this would work for any GJNUM, but with lower performance
! !NEC$ SHORTLOOP
!           DO j=1,Mesh%GJNUM
!             WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m).GE.0.0 )
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
!                 = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+j-1,Mesh%KMIN:Mesh%KMAX,m)
!             ELSEWHERE
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
!                 =  pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m)
!             END WHERE
!           END DO
          WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m).GE.0.0 )
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMIN,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+1,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMIN+1,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m)
          ELSEWHERE
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMIN,Mesh%KMIN:Mesh%KMAX,m) &
              =  pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMIN+1,Mesh%KMIN:Mesh%KMAX,m) &
              =  pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m)
          END WHERE
        CASE(CUSTOM_KEPLER)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
            = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m) &
            + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA)&
            * this%invRscale(Mesh%IMIN:Mesh%IMAX,j,Mesh%KMIN:Mesh%KMAX) &
            - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA
          END DO
        CASE(CUSTOM_ANGKEPLER)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX,m) &
            = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX,m) &
            + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA)&
            * this%Rscale(Mesh%IMIN:Mesh%IMAX,j,Mesh%KMIN:Mesh%KMAX) &
            - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN-j,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA
          END DO
        CASE DEFAULT ! defaults to NO_GRADIENTS
          CALL this%Error("boundary_custom::SetBoundaryData","southern boundary: undefined conditions")
        END SELECT
      END DO
    CASE(NORTH)
      DO m=1,Physics%VNUM
        SELECT CASE(this%cbtype(m))
        CASE(CUSTOM_NOGRAD)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_PERIOD)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN+j-1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLECT)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-j+1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_REFLNEG)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-j+1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_EXTRAPOL)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = (j+1)*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              - j*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-1,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_FIXED)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = this%data(Mesh%IMIN:Mesh%IMAX,j,Mesh%KMIN:Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_LOGEXPOL)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              * ABS(pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              / pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-1,Mesh%KMIN:Mesh%KMAX,m))**j
          END DO
        CASE(CUSTOM_OUTFLOW)
! REMARK: this would work for any GJNUM, but with lower performance
! !NEC$ SHORTLOOP
!           DO j=1,Mesh%GJNUM
!             WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m).LE.0.0 )
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
!                 = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-j+1,Mesh%KMIN:Mesh%KMAX,m)
!             ELSEWHERE
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
!                 = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
!             END WHERE
!           END DO
          WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m).LE.0.0 )
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX-1,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMAX-1,Mesh%KMIN:Mesh%KMAX,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          ELSEWHERE
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMAX,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JGMAX-1,Mesh%KMIN:Mesh%KMAX,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m)
          END WHERE
        CASE(CUSTOM_KEPLER)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA)&
              * this%invRscale(Mesh%IMIN:Mesh%IMAX,j,Mesh%KMIN:Mesh%KMAX) &
              - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX)*Mesh%OMEGA
          END DO
        CASE(CUSTOM_ANGKEPLER)
!NEC$ SHORTLOOP
          DO j=1,Mesh%GJNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX,m) &
              = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,m) &
              + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA)&
              * this%Rscale(Mesh%IMIN:Mesh%IMAX,j,Mesh%KMIN:Mesh%KMAX) &
              - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMAX+j,Mesh%KMIN:Mesh%KMAX)**2*Mesh%OMEGA
          END DO
        CASE DEFAULT
          CALL this%Error("boundary_custom::SetBoundaryData","northern boundary: undefined conditions")
        END SELECT
      END DO
    CASE(BOTTOM)
      DO m=1,Physics%VNUM
        SELECT CASE(this%cbtype(m))
        CASE(CUSTOM_NOGRAD)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m)
          END DO
        CASE(CUSTOM_PERIOD)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-k+1,m)
          END DO
        CASE(CUSTOM_REFLECT)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+k-1,m)
          END DO
        CASE(CUSTOM_REFLNEG)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+k-1,m)
          END DO
        CASE(CUSTOM_EXTRAPOL)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = (k+1)*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m) &
              - k*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+1,m)
          END DO
        CASE(CUSTOM_FIXED)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = this%data(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,k,m)
          END DO
        CASE(CUSTOM_LOGEXPOL)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m) &
              * ABS(pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m) &
              / pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+1,m))**k
          END DO
        CASE(CUSTOM_OUTFLOW)
! REMARK: this would work for any GKNUM, but with lower performance
! !NEC$ SHORTLOOP
!           DO k=1,Mesh%GKNUM
!             WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m).GE.0.0 )
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
!                 = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+k-1,m)
!             ELSEWHERE
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
!                 = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m)
!             END WHERE
!           END DO
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m).GE.0.0 )
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMIN,m) &
                = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+1,m)
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMIN+1,m) &
                = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m)
            ELSEWHERE
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMIN,m) &
                = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m)
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMIN+1,m) &
                = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m)
            END WHERE
          END DO
        CASE(CUSTOM_KEPLER)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m) &
              + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN)*Mesh%OMEGA)&
              * this%invRscale(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,k) &
              - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k)*Mesh%OMEGA
          END DO
        CASE(CUSTOM_ANGKEPLER)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k,m) &
              = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN,m) &
              + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN)**2*Mesh%OMEGA)&
              * this%invRscale(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,k) &
              - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN-k)**2*Mesh%OMEGA
          END DO
        CASE DEFAULT
          CALL this%Error("boundary_custom::SetBoundaryData","bottom boundary: undefined conditions")
        END SELECT
      END DO
    CASE(TOP)
      DO m=1,Physics%VNUM
        SELECT CASE(this%cbtype(m))
        CASE(CUSTOM_NOGRAD)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m)
          END DO
        CASE(CUSTOM_PERIOD)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN+k-1,m)
          END DO
        CASE(CUSTOM_REFLECT)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-k+1,m)
          END DO
        CASE(CUSTOM_REFLNEG)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-k+1,m)
          END DO
        CASE(CUSTOM_EXTRAPOL)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = (k+1)*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m) &
              - k*pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-1,m)
          END DO
        CASE(CUSTOM_FIXED)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = this%data(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,k,m)
          END DO
        CASE(CUSTOM_LOGEXPOL)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m) &
              * ABS(pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m) &
              / pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-1,m))**k
          END DO
        CASE(CUSTOM_OUTFLOW)
! REMARK: this would work for any GKNUM, but with lower performance
! !NEC$ SHORTLOOP
!           DO k=1,Mesh%GKNUM
!             WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m).LE.0.0)
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
!                 = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-k+1,m)
!             ELSEWHERE
!               pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
!                 = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m)
!             END WHERE
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            WHERE (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m).LE.0.0)
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMAX,m) &
                = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX-1,m)
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMAX-1,m) &
                = -pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m)
            ELSEWHERE
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMAX,m) &
                = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m)
              pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KGMAX-1,m) &
                = pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m)
            END WHERE
          END DO
        CASE(CUSTOM_KEPLER)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m) &
              + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX)*Mesh%OMEGA)&
              * this%invRscale(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,k) &
              - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k)*Mesh%OMEGA
          END DO
        CASE(CUSTOM_ANGKEPLER)
!NEC$ SHORTLOOP
          DO k=1,Mesh%GKNUM
            pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k,m) &
              = (pvar(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX,m) &
              + this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX)**2*Mesh%OMEGA)&
              * this%invRscale(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,k) &
              - this%radius(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMAX+k)**2*Mesh%OMEGA
          END DO
        CASE DEFAULT
          CALL this%Error("boundary_custom::SetBoundaryData","top boundary: undefined conditions")
        END SELECT
      END DO
    END SELECT
  END SUBROUTINE SetBoundaryData

  SUBROUTINE SetCustomBoundaries(this,Mesh,Physics,cbtype,kepler_radius)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(boundary_custom), INTENT(INOUT) :: this
    CLASS(mesh_base),       INTENT(IN)    :: Mesh
    CLASS(physics_base),    INTENT(IN)    :: Physics
    INTEGER, DIMENSION(1:Physics%VNUM)    :: cbtype
    REAL, DIMENSION(:,:,:), POINTER, OPTIONAL :: kepler_radius
    !------------------------------------------------------------------------!
    INTEGER            :: i,j,k,err = 0
    !------------------------------------------------------------------------!
    this%cbtype(:) = cbtype(:)
    IF (ANY(this%cbtype(:).EQ.CUSTOM_FIXED)) THEN
      SELECT CASE(this%GetDirection())
      CASE(WEST,EAST)
        ALLOCATE(this%data(Mesh%GINUM,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX,Physics%VNUM), &
              STAT=err)
      CASE(SOUTH,NORTH)
        ALLOCATE(this%data(Mesh%IMIN:Mesh%IMAX,Mesh%GJNUM,Mesh%KMIN:Mesh%KMAX,Physics%VNUM), &
              STAT=err)
      CASE(BOTTOM,TOP)
        ALLOCATE(this%data(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%GKNUM,Physics%VNUM), &
              STAT=err)
      END SELECT
      IF (err.NE.0) CALL this%Error("SetCustomBoundaries","Unable to allocate memory.")
      this%data(:,:,:,:) = 0.0
    END IF

    IF (ANY(this%cbtype(:).EQ.CUSTOM_OUTFLOW)) THEN
      SELECT CASE(this%GetDirection())
      CASE(WEST,EAST)
        IF (Mesh%GINUM.NE.2) CALL this%Error("SetCustomBoundaries","GINUM must be 2 for outflow boundaries")
      CASE(SOUTH,NORTH)
        IF (Mesh%GJNUM.NE.2) CALL this%Error("SetCustomBoundaries","GJNUM must be 2 for outflow boundaries")
      CASE(BOTTOM,TOP)
        IF (Mesh%GKNUM.NE.2) CALL this%Error("SetCustomBoundaries","GKNUM must be 2 for outflow boundaries")
      END SELECT
    END IF

    IF (ANY(this%cbtype(:).EQ.CUSTOM_KEPLER)) THEN
      SELECT CASE(this%GetDirection())
      CASE(WEST,EAST)
        ALLOCATE(this%invRscale(Mesh%GINUM,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX), &
              STAT=err)
      CASE(SOUTH,NORTH)
        ALLOCATE(this%invRscale(Mesh%IMIN:Mesh%IMAX,Mesh%GJNUM,Mesh%KMIN:Mesh%KMAX), &
              STAT=err)
      CASE(BOTTOM,TOP)
        ALLOCATE(this%invRscale(Mesh%IMIN:Mesh%IMAX,Mesh%KGMIN:Mesh%JMAX,Mesh%GKNUM), &
              STAT=err)
      END SELECT
      IF (err.NE.0) CALL this%Error("SetCustomBoundaries","Unable to allocate memory.")

      IF (PRESENT(kepler_radius)) THEN
        this%radius => kepler_radius
        IF (Mesh%OMEGA.GT.TINY(Mesh%OMEGA)) &
          CALL this%Warning("SetCustomBoundaries", &
            "user supplied radius and rotating frame may yield unexpected/wrong results")
      ELSE
        this%radius => Mesh%radius%bcenter
      END IF

      SELECT CASE(this%GetDirection())
      CASE(WEST)
        FORALL (i=1:Mesh%GINUM,j=Mesh%JMIN:Mesh%JMAX,k=Mesh%KMIN:Mesh%KMAX) &
          this%invRscale(i,j,k) = this%radius(Mesh%IMIN,j,k) / this%radius(Mesh%IMIN-i,j,k)
      CASE(EAST)
        FORALL (i=1:Mesh%GINUM,j=Mesh%JMIN:Mesh%JMAX,k=Mesh%KMIN:Mesh%KMAX) &
          this%invRscale(i,j,k) = this%radius(Mesh%IMAX,j,k) / this%radius(Mesh%IMAX+i,j,k)
      CASE(SOUTH)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=1:Mesh%GjNUM,k=Mesh%KMIN:Mesh%KMAX) &
          this%invRscale(i,j,k) = this%radius(i,Mesh%JMIN,k) / this%radius(i,Mesh%JMIN-j,k)
      CASE(NORTH)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=1:Mesh%GjNUM,k=Mesh%KMIN:Mesh%KMAX) &
          this%invRscale(i,j,k) = this%radius(i,Mesh%JMAX,k) / this%radius(i,Mesh%JMAX+j,k)
      CASE(BOTTOM)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=Mesh%JMIN:Mesh%JMAX,k=1:Mesh%GKNUM) &
          this%invRscale(i,j,k) = this%radius(i,j,Mesh%KMIN) / this%radius(i,j,Mesh%KMIN-k)
      CASE(TOP)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=Mesh%JMIN:Mesh%JMAX,k=1:Mesh%GKNUM) &
          this%invRscale(i,j,k) = this%radius(i,j,Mesh%KMAX) / this%radius(i,j,Mesh%KMAX+k)
      END SELECT
      this%invRscale(:,:,:) = SQRT(this%invRscale(:,:,:))
    END IF

    IF (ANY(this%cbtype(:).EQ.CUSTOM_ANGKEPLER)) THEN
      SELECT CASE(this%GetDirection())
      CASE(WEST,EAST)
        ALLOCATE(this%Rscale(Mesh%GINUM,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX), &
              STAT=err)
      CASE(SOUTH,NORTH)
        ALLOCATE(this%Rscale(Mesh%IMIN:Mesh%IMAX,Mesh%GJNUM,Mesh%KMIN:Mesh%KMAX), &
              STAT=err)
      CASE(BOTTOM,TOP)
        ALLOCATE(this%Rscale(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%GKNUM), &
              STAT=err)
      END SELECT

      IF (PRESENT(kepler_radius)) THEN
        this%radius => kepler_radius
        IF (Mesh%OMEGA.GT.TINY(Mesh%OMEGA)) &
          CALL this%Warning("SetCustomBoundaries", &
            "user supplied radius and rotating frame may yield unexpected/wrong results")
      ELSE
        this%radius => Mesh%radius%bcenter
      END IF

      IF (err.NE.0) CALL this%Error("SetCustomBoundaries","Unable to allocate memory.")
      SELECT CASE(this%GetDirection())
      CASE(WEST)
        FORALL (i=1:Mesh%GINUM,j=Mesh%JMIN:Mesh%JMAX,k=Mesh%KMIN:Mesh%KMAX) &
          this%Rscale(i,j,k) = this%radius(Mesh%IMIN-i,j,k) / this%radius(Mesh%IMIN,j,k)
      CASE(EAST)
        FORALL (i=1:Mesh%GINUM,j=Mesh%JMIN:Mesh%JMAX,k=Mesh%KMIN:Mesh%KMAX) &
          this%Rscale(i,j,k) = this%radius(Mesh%IMAX+i,j,k) / this%radius(Mesh%IMAX,j,k)
      CASE(SOUTH)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=1:Mesh%GjNUM,k=Mesh%KMIN:Mesh%KMAX) &
          this%Rscale(i,j,k) = this%radius(i,Mesh%JMIN-j,k) / this%radius(i,Mesh%JMIN,k)
      CASE(NORTH)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=1:Mesh%GjNUM,k=Mesh%KMIN:Mesh%KMAX) &
          this%Rscale(i,j,k) = this%radius(i,Mesh%JMAX+j,k) / this%radius(i,Mesh%JMAX,k)
      CASE(BOTTOM)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=Mesh%JMIN:Mesh%JMAX,k=1:Mesh%GKNUM) &
          this%Rscale(i,j,k) = this%radius(i,j,Mesh%KMIN-k) / this%radius(i,j,Mesh%KMIN)
      CASE(TOP)
        FORALL (i=Mesh%IMIN:Mesh%IMAX,j=Mesh%JMIN:Mesh%JMAX,k=1:Mesh%GKNUM) &
          this%Rscale(i,j,k) = this%radius(i,j,Mesh%KMAX+k) / this%radius(i,j,Mesh%KMAX)
      END SELECT
      this%Rscale(:,:,:) = SQRT(this%Rscale(:,:,:))
    END IF
  END SUBROUTINE

  SUBROUTINE Finalize(this)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(boundary_custom), INTENT(INOUT) :: this
    !------------------------------------------------------------------------!
    IF (ALLOCATED(this%data)) DEALLOCATE(this%data)
    IF (ALLOCATED(this%cbtype)) DEALLOCATE(this%cbtype)
    IF (ALLOCATED(this%Rscale)) DEALLOCATE(this%Rscale)
    IF (ALLOCATED(this%invRscale)) DEALLOCATE(this%invRscale)

    CALL this%Finalize_base()
  END SUBROUTINE Finalize
END MODULE boundary_custom_mod
