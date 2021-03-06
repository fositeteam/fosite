!#############################################################################
!#                                                                           #
!# fosite - 3D hydrodynamical simulation program                             #
!# module: timedisc_cashkarp.f90                                             #
!#                                                                           #
!# Copyright (C) 2011-2018                                                   #
!# Björn Sperling   <sperling@astrophysik.uni-kiel.de>                       #
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
!> \author Björn Sperling
!! \author Tobias Illenseer
!!
!! \brief subroutines for embedded Runge-Kutta method
!!
!! Reference:
!! - \cite engeln2006 G.Engeln-Müllges & F.Reutter (Book)
!! - \cite cash1990 Cash, J. R., & Karp, A. H. (1990). A variable order
!!    Runge-Kutta method for initial value problems with rapidly varying
!!    right-hand sides. ACM Transactions on Mathematical Software (TOMS),
!!    16(3), 201-222.
!!
!! \extends timedisc_common
!! \ingroup timedisc
!----------------------------------------------------------------------------!
MODULE timedisc_cashkarp_mod
  USE timedisc_base_mod
  USE mesh_base_mod
  USE fluxes_base_mod
  USE boundary_base_mod
  USE physics_base_mod
  USE sources_base_mod
  USE timedisc_rkfehlberg_mod
  USE common_dict
  IMPLICIT NONE
  !--------------------------------------------------------------------------!
  PRIVATE
  TYPE, EXTENDS (timedisc_rkfehlberg) :: timedisc_cashkarp
  CONTAINS
    PROCEDURE :: InitTimedisc_cashkarp
    PROCEDURE :: SetButcherTableau
    PROCEDURE :: Finalize
  END TYPE timedisc_cashkarp
  !--------------------------------------------------------------------------!
  CHARACTER(LEN=32), PARAMETER :: ODEsolver_name = "Cash-Karp method"

  !--------------------------------------------------------------------------!
  PUBLIC :: &
       ! types
       timedisc_cashkarp
  !--------------------------------------------------------------------------!

CONTAINS

  SUBROUTINE InitTimedisc_cashkarp(this,Mesh,Physics,config,IO)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(timedisc_cashkarp), INTENT(INOUT) :: this
    CLASS(mesh_base),         INTENT(INOUT) :: Mesh
    CLASS(physics_base),      INTENT(IN)    :: Physics
    TYPE(Dict_TYP), POINTER :: config, IO
    !------------------------------------------------------------------------!
    ! set default order
    CALL GetAttr(config, "order", this%order, 5)

    !set number of coefficients
    SELECT CASE(this%GetOrder())
    CASE(5)
      this%m = 6
    CASE DEFAULT
      CALL this%Error("InitTimedisc_cashkarp","time order must be 5")
    END SELECT

    CALL this%InitTimedisc(Mesh,Physics,config,IO,CASH_KARP,ODEsolver_name)
  END SUBROUTINE InitTimedisc_cashkarp

  !> set coefficients for Cash-Karp scheme
  SUBROUTINE SetButcherTableau(this)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(timedisc_cashkarp)   :: this
    !------------------------------------------------------------------------!
    SELECT CASE(this%GetOrder())
    CASE(5)
      this%b_high = (/ 37.0/378.0, 0.0, 250.0/621.0, 125.0/594.0, 0.0, 512.0/1771.0 /)
      this%b_low  = (/ 2825.0/27648.0, 0.0, 18575.0/48384.0, 13525.0/55296.0, &
                      277.0/14336.0, 0.25 /)
      this%c  = (/ 0.0, 0.2, 0.3, 0.6, 1.0, 7.0/8.0  /)
      this%a  = TRANSPOSE(RESHAPE((/ &
                0.0, 0.0, 0.0, 0.0, 0.0, 0.0, &
                0.2, 0.0, 0.0, 0.0, 0.0, 0.0, &
                0.075, 0.225, 0.0, 0.0, 0.0, 0.0, &
                0.3, -0.9, 1.2, 0.0, 0.0, 0.0, &
                -11.0/54.0 , 2.5, -70.0/27.0, 35.0/27.0, 0.0, 0.0, &
                1631.0/55296.0, 175.0/512.0, 575.0/13824.0, &
                44275.0/110592.0, 253.0/4096.0, 0.0/),(/this%m,this%m/)))
    CASE DEFAULT
       CALL this%Error("timedisc_cashkarp::SetButcherTableau","only order 5 supported")
    END SELECT
  END SUBROUTINE SetButcherTableau

  SUBROUTINE Finalize(this)
    IMPLICIT NONE
    !-----------------------------------------------------------------------!
    CLASS(timedisc_cashkarp) :: this
    !-----------------------------------------------------------------------!
    CALL this%timedisc_rkfehlberg%Finalize()
  END SUBROUTINE
END MODULE timedisc_cashkarp_mod
