!#############################################################################
!#                                                                           #
!# fosite - 3D hydrodynamical simulation program                             #
!# module: sources_viscosity.f90                                             #
!#                                                                           #
!# Copyright (C) 2008-2019                                                   #
!# Bjoern Sperling <sperling@astrophysik.uni-kiel.de>                        #
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
!# along with Mesh program; if not, write to the Free Software               #
!# Foundation, Inc., 675 Mass Ave, Cambridge, MA 02139, USA.                 #
!#                                                                           #
!#############################################################################
!> \addtogroup sources
!! - parameters of \link sources_viscosity \endlink as key-values
!! \key{vismodel,INTEGER,viscosity model}
!! \key{dynconst,REAL,dynamic viscosity constant,0.1}
!! \key{bulkconst,REAL,bulk viscosity constant,-2/3*dynconst}
!! \key{cvis,REAL,viscous courant number,0.5}
!! \key{output/stress,INTEGER,enable(=1) output of the stress tensor,0}
!! \key{output/dynvis,INTEGER,enable(=1) output of dynamic viscosity,0}
!! \key{output/kinvis,INTEGER,enable(=1) output of kinematic viscosity,0}
!! \key{output/bulkvis,INTEGER,enable(=1) output of bulk viscosity,0}
!----------------------------------------------------------------------------!
!> \author Björn Sperling
!! \author Tobias Illenseer
!!
!! \brief computes momentum and energy sources due to shear stresses
!!
!! The momentum sources are given by the divergence of the stress tensor
!! \f$ \nabla\cdot\mathbf{T} \f$ whereas the energy source term, i.e. heating
!! due to dissipation, is given by the divergence of the stress tensor
!! projected on the velocity field \f$ \nabla\cdot\left(\mathbf{T}\cdot\mathbf{v}\right) \f$ .
!!
!! The components of the stress tensor
!! \f[ \mathbf{T} = \eta\left(\nabla\mathbf{v} + \nabla\mathbf{v}^\mathsf{T}\right)
!!     + \mu_\mathrm{b} \nabla\cdot\mathbf{v}
!! \f]
!! are computed in the physics modules, see e.g. \ref physics_euler.calcstresses_euler
!! for any given curvilinear orthonormal geometry.
!!
!! For a description of the currently supported (effective turbulent) viscosity
!! models see \ref updateviscosity
!!
!! \extends sources_base
!! \ingroup sources
!----------------------------------------------------------------------------!
MODULE sources_viscosity_mod
  USE sources_base_mod
  USE physics_base_mod
  USE fluxes_base_mod
  USE mesh_base_mod
  USE marray_base_mod
  USE marray_compound_mod
  USE logging_base_mod
  USE common_dict
  IMPLICIT NONE
  !--------------------------------------------------------------------------!
  PRIVATE
    ! flags for viscosity model
    INTEGER,PARAMETER :: MOLECULAR = 1     ! constant viscosity
    INTEGER,PARAMETER :: ALPHA     = 2     ! Shakura-Sunyaev prescription
    INTEGER,PARAMETER :: BETA      = 3     ! Duschl prescription
    INTEGER,PARAMETER :: PRINGLE   = 4     ! constant kinematic viscosity
    INTEGER,PARAMETER :: ALPHA_ALT = 5     ! alternative Shakura-Sunyaev
    CHARACTER(LEN=32),PARAMETER, DIMENSION(5) :: viscosity_name = (/ &
                                     "constant viscosity              ", &
                                     "turbulent Shakura-Sunyaev       ", &
                                     "turbulent Duschl                ", &
                                     "const. kinematic viscosity      ", &
                                     "alternative Shakura-Sunyaev     "/)


  TYPE, EXTENDS(sources_base) :: sources_viscosity
    CHARACTER(LEN=32) :: source_name = "viscosity of Newtonian fluid"
    CLASS(logging_base), ALLOCATABLE :: viscosity
    CLASS(marray_base), ALLOCATABLE  :: ephir, &    !< azimuthal unit vector */ distance to axis
                                     ephir_tmp
    REAL :: dynconst,bulkconst                      !< viscosity const.
    REAL, DIMENSION(:,:,:), POINTER  :: dynvis, &   !< dynamic viscosity
                                        kinvis, &   !< kinematic viscosity
                                        bulkvis, &  !< bulk viscosity
                                        envelope
     REAL, DIMENSION(:,:,:), POINTER :: &           !< comp. of stress tensor
           btxx,btyy,btzz,btxy,btxz,btyz,tmp,tmp2,tmp3
     REAL, DIMENSION(:,:), POINTER   :: &
           Sxx,Syy,Szz,Sxy,Sxz,Syz
  CONTAINS
    PROCEDURE :: InitSources_viscosity
    PROCEDURE :: InfoSources
    PROCEDURE :: SetOutput
    PROCEDURE :: UpdateViscosity
    PROCEDURE :: ExternalSources_single
    PROCEDURE :: CalcTimestep_single

    PROCEDURE :: Finalize
  END TYPE
  !--------------------------------------------------------------------------!
 PUBLIC :: &
       ! types
       Sources_viscosity, &
       ! constants
       MOLECULAR,ALPHA,BETA,PRINGLE,ALPHA_ALT,viscosity_name
  !--------------------------------------------------------------------------!

CONTAINS

  SUBROUTINE InitSources_viscosity(this,Mesh,Physics,Fluxes,config,IO)
    USE geometry_base_mod
    USE geometry_cylindrical_mod, ONLY: geometry_cylindrical
    USE geometry_logcylindrical_mod, ONLY: geometry_logcylindrical
    USE physics_eulerisotherm_mod, ONLY : physics_eulerisotherm
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(Sources_viscosity) :: this
    CLASS(Mesh_base)    :: Mesh
    CLASS(Physics_base) :: Physics
    CLASS(Fluxes_base)  :: Fluxes
    TYPE(Dict_TYP),POINTER :: config,IO
    INTEGER           :: stype
    !------------------------------------------------------------------------!
    INTEGER           :: err, viscosity_number ,k,l
    !------------------------------------------------------------------------!
    INTENT(IN)        :: Mesh,Physics,Fluxes
    !------------------------------------------------------------------------!
    CALL GetAttr(config, "stype", stype)
    CALL this%InitLogging(stype,this%source_name)
    ! viscosity model
    CALL GetAttr(config, "vismodel", viscosity_number)
    ALLOCATE(logging_base::this%viscosity)
    CALL this%viscosity%InitLogging(viscosity_number,viscosity_name(viscosity_number))


    IF (.NOT.Fluxes%Initialized()) &
         CALL this%Error("InitSources_viscosity","fluxes module uninitialized")

    ! check mesh
    IF (Mesh%GetType().NE.MIDPOINT) &
         CALL this%Error("InitSources_viscosity", &
         "only midpoint rule is currently supported")


    ! dynamic viscosity constant
    CALL GetAttr(config, "dynconst", this%dynconst, 0.1)
    ! bulk viscosity constant
    ! At the moment this only affects the molecular viscosity. The default
    ! value refers to a trace free viscosity tensor.
    ! All other viscosity models should always be trace free. Therefore this
    ! is hard coded and cannot be changed.
    CALL GetAttr(config, "bulkconst", this%bulkconst, -2./3.*this%dynconst)

    ! set viscous courant number
    CALL GetAttr(config, "cvis", this%cvis, 0.5)

    ! enable the envelope mask field, which scales the viscosity with [0,1]
    CALL GetAttr(config, "envelope", this%use_envelope, 0)
    ALLOCATE(this%dynvis(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%kinvis(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%bulkvis(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%btxx(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%btyy(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%btzz(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%btxy(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%btxz(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         this%btyz(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX), &
         STAT=err)
    IF (err.NE.0) &
         CALL this%Error("InitSources_viscosity","Memory allocation failed.")
    ! do the model specific initialization
    SELECT CASE(this%viscosity%GetType())
    CASE(MOLECULAR,PRINGLE)
       ! do nothing
    CASE(ALPHA,BETA)
      ! compute the projector to determine the local angular velocity
      ! ATTENTION: it is always assumed that the fluid rotates around the z-axis
      SELECT TYPE(phys => Physics)
      CLASS IS(physics_eulerisotherm)
        ALLOCATE(this%ephir,this%ephir_tmp,STAT=err)
        IF (err.NE.0) &
          CALL this%Error("InitSources_viscosity","Memory allocation failed.")
        this%ephir_tmp = marray_base(3)
        this%ephir = marray_base(3)
        ! compute ephi/r (r: distance to z-axis, ephi: azimuthal unit vector)
        ! set cartesian vector components using cartesian coordinates
        this%ephir%data4d(:,:,:,1) = -Mesh%cart%bcenter(:,:,:,2) / Mesh%radius%bcenter(:,:,:)**2
        this%ephir%data4d(:,:,:,2) = Mesh%cart%bcenter(:,:,:,1) / Mesh%radius%bcenter(:,:,:)**2
        this%ephir%data4d(:,:,:,3) = 0.0
        ! convert to curvilinear vector components
        CALL Mesh%geometry%Convert2Curvilinear(Mesh%curv%bcenter,this%ephir%data4d,this%ephir_tmp%data4d)
        ! reduce vector components to match Physics%VDIM
        IF (phys%VDIM.LT.3) THEN
          CALL this%ephir%Destroy()
          this%ephir = marray_base(phys%VDIM)
        END IF
        ! copy vector components actually used
        l = 1
        DO k=1,3
          IF (phys%vector_component_enabled(k)) THEN
            this%ephir%data2d(:,l) = this%ephir_tmp%data2d(:,k)
            l = l + 1
          END IF
        END DO
        ! destroy temporary marray
        CALL this%ephir_tmp%Destroy()
        DEALLOCATE(this%ephir_tmp)
      CLASS DEFAULT
        CALL this%Error("InitSources_viscosity",&
               "Physics not supported for alpha-/beta-viscosity")
      END SELECT
    CASE(ALPHA_ALT)
       !> \todo check if this is really sufficient
       CALL this%Error("InitSources_viscosity",&
               "alternative alpha-viscosity currently not supported")
!        IF (Physics%VDIM.NE.2) &
!           CALL this%Error("InitSources_viscosity",&
!                "alternative alpha-viscosity works only for flat disks")
   !    IF (.NOT.Timedisc%always_update_bccsound) &
   !       CALL Error(this,"InitSources_viscosity","always_update_bccsound must be enabled in timedisc")
    CASE DEFAULT
       CALL this%Error("InitSources_viscosity",&
            "Viscosity prescription not supported.")
    END SELECT
    ! set initial time to negative value;
    ! this guarantees update of viscosity for time t=0.0
    this%time = -1.0
    ! initialize viscosity arrays
    this%dynvis(:,:,:)  = this%dynconst
    this%bulkvis(:,:,:) = this%bulkconst
    ! set stress tensor arrays to zero
    this%btxx(:,:,:) = 0.0
    this%btyy(:,:,:) = 0.0
    this%btzz(:,:,:) = 0.0
    this%btxy(:,:,:) = 0.0
    this%btxz(:,:,:) = 0.0
    this%btyz(:,:,:) = 0.0
    IF(this%use_envelope.EQ.1) THEN
      ALLOCATE(this%envelope(Mesh%IGMIN:Mesh%IGMAX,Mesh%JGMIN:Mesh%JGMAX,Mesh%KGMIN:Mesh%KGMAX),&
               STAT=err)
      IF (err.NE.0) &
        CALL this%Error("InitSources_viscosity","Memory allocation failed.")
      this%envelope = 1.
    END IF
    CALL this%SetOutput(Mesh,Physics,config,IO)
    IF (this%GetType().EQ.ALPHA_ALT) this%update_disk_height = .True.

    CALL this%InitSources(Mesh,Fluxes,Physics,config,IO)

  END SUBROUTINE InitSources_viscosity

  SUBROUTINE SetOutput(this,Mesh,Physics,config,IO)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(Sources_viscosity),INTENT(IN) :: this
    CLASS(Mesh_base) ,INTENT(IN)      :: Mesh
    CLASS(Physics_base),INTENT(IN)    :: Physics
    TYPE(Dict_TYP),POINTER  :: config,IO
    !------------------------------------------------------------------------!
    INTEGER              :: valwrite
    !------------------------------------------------------------------------!
   ! Hier wird der Stresstensor per default in 3D ausgegeben! Vorher nur in 2D plus abhängig
   ! von der Physik auch die Komponenten der dritten Dimension
    CALL GetAttr(config, "output/stress", valwrite, 0)
    IF (valwrite .EQ. 1) THEN
       CALL SetAttr(IO, "stress:xx", this%btxx(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
       CALL SetAttr(IO, "stress:xy", this%btxy(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
       CALL SetAttr(IO, "stress:xz", this%btxz(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
       CALL SetAttr(IO, "stress:yy", this%btyy(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
       CALL SetAttr(IO, "stress:yz", this%btyz(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
       CALL SetAttr(IO, "stress:zz", this%btzz(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))
    END IF

    CALL GetAttr(config, "output/dynvis", valwrite, 0)
    IF (valwrite .EQ. 1) &
         CALL SetAttr(IO,"dynvis", this%dynvis(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))

    CALL GetAttr(config, "output/kinvis", valwrite, 0)
    IF (valwrite .EQ. 1) &
         CALL SetAttr(IO, "kinvis", this%kinvis(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))

    CALL GetAttr(config, "output/bulkvis", valwrite, 0)
    IF (valwrite .EQ. 1) &
         CALL SetAttr(IO, "bulkvis", this%bulkvis(Mesh%IMIN:Mesh%IMAX,Mesh%JMIN:Mesh%JMAX,Mesh%KMIN:Mesh%KMAX))

  END SUBROUTINE SetOutput


  SUBROUTINE InfoSources(this,Mesh)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(Sources_viscosity),INTENT(IN) :: this
    CLASS(Mesh_base),INTENT(IN)         :: Mesh
    !------------------------------------------------------------------------!
    CHARACTER(LEN=32) :: dynconst_str,bulkconst_str
    !------------------------------------------------------------------------!
    WRITE (dynconst_str,'(ES9.2)') this%dynconst
    WRITE (bulkconst_str,'(ES9.2)') this%bulkconst
    CALL this%Info("            viscosity model:   " // this%viscosity%GetName())
    SELECT CASE(this%viscosity%GetType())
    CASE(MOLECULAR)
       CALL this%Info("            dynamic viscosity: " // TRIM(dynconst_str))
       CALL this%Info("            bulk viscosity:    " // TRIM(bulkconst_str))
    CASE(ALPHA,ALPHA_ALT)
       CALL this%Info("            alpha:             " // TRIM(dynconst_str))
    CASE(BETA)
       CALL this%Info("            beta:              " // TRIM(dynconst_str))
    CASE(PRINGLE)
       CALL this%Info("            kinemat. viscosity:" // TRIM(dynconst_str))
    END SELECT
  END SUBROUTINE InfoSources


  !> \public updates dynamic and bulk viscosity
  !!
  !! Currently 5 different viscosity prescriptions are supported
  !!   -# molecular: constant dynamic and bulk viscosity coefficients
  !!      (no temperature dependence implemented yet)
  !!   -# alpha: Shakura-Sunyaev \f$ \alpha \f$-viscosity \cite shakura1973 \n
  !!      The kinematic effective turbulent viscosity is set according to
  !!      \f[ \nu = \alpha \frac{c_s^2}{\Omega} \f]
  !!      with \f$ \alpha < 1 \f$ . It can be derived from the ansatz
  !!      \f[ T_{r\varphi} = \nu \Sigma r \frac{d\Omega}{d r} = -\tilde{\alpha} \Pi \f]
  !!      using \f$ \Pi = \gamma c_s^2 \Sigma \f$ and 
  !!      \f[ A = \left(-\frac{d\ln\Omega}{d\ln r}\right)^{-1} \approx \frac{2}{3}. \f]
  !!      where the approximation holds for Keplerian disks (see \cite kato2008 , Section 3.2.1).
  !!      The two non-dimensional parameters are then related according to
  !!      \f$ \alpha = \tilde{\alpha} \gamma A \f$.
  !!   -# alpha_alt: alternative Shakura-Sunyaev \f$ \alpha \f$-viscosity \cite shakura1973 \n
  !!      This is an alternative derived from the prescription above using the relation
  !!      \f$ c_s = h \Omega \f$ to replace one \f$ c_s \f$ in the viscosity formula:
  !!      \f[ \nu = \alpha c_s h \f]
  !!      Attention! This works only for geometrically thin Keplerian disks and requires
  !!      computation of the pressure scale height \f$ h \f$
  !!      (see \ref sources_gravity_mod.calcdiskheight )
  !!   -# beta: Duschl-Strittmatter-Biermann \f$ \beta \f$-viscosity \cite duschl2000 \n
  !!      The kinematic effective turbulent viscosity is set according to
  !!      \f[ \nu = \beta r v_\varphi = \beta r^2 \Omega \f]
  !!      with local angular velocity \f$ \Omega \f$ and dimensionless parameter
  !!      \f$ \beta \approx \mathfrak{Re}_\mathrm{crit}^{-1} \ll 1 \f$ where the
  !!      critical Reynolds number is of the order of \f$ 10^3 \f$ .
  !!   -# pringle: constant kinematic viscosity
  !!
  !! In cases 2. -- 5. bulk viscosity \f$ \mu_\mathrm{b} \f$ is set using the Stokes'
  !! hypothesis, namely that the volume viscosity is zero, i.e.
  !! \f[ \zeta = 0 \Leftrightarrow \mu_b = -\frac{2}{3}\eta \f] .
  SUBROUTINE UpdateViscosity(this,Mesh,Physics,Fluxes,time,pvar,cvar)
    USE physics_eulerisotherm_mod, ONLY : physics_eulerisotherm, statevector_eulerisotherm
    USE physics_euler_mod, ONLY : physics_euler, statevector_euler
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(Sources_viscosity),INTENT(INOUT) :: this
    CLASS(Mesh_base),INTENT(IN)         :: Mesh
    CLASS(Physics_base),INTENT(INOUT)   :: Physics
    CLASS(Fluxes_base),INTENT(IN)       :: Fluxes
    REAL,INTENT(IN)                     :: time
    CLASS(marray_compound),INTENT(INOUT)   :: pvar,cvar
    !------------------------------------------------------------------------!
    INTEGER           :: l
    !------------------------------------------------------------------------!
    ! only update viscosity if time has changed
    IF ((time.NE.this%time) .OR. (time .EQ. 0.)) THEN
       ! Set the dynamic viscosity
       SELECT CASE(this%viscosity%GetType())
       CASE(MOLECULAR)
          ! do nothing, since it has already been initialized
          ! in InitSources_viscosity
       CASE(ALPHA)
          ! compute Shakura-Sunyaev type alpha viscosity
          ! depending on physics and type of statevector (with or w/o pressure)
          SELECT TYPE(phys => Physics)
          CLASS IS(physics_eulerisotherm)
            SELECT TYPE(p => pvar)
            CLASS IS(statevector_eulerisotherm)
              ! project velocity on ephi/r -> local angular velocity
              ! use dynvis as temporary storage
              this%dynvis(:,:,:) = this%ephir%data4d(:,:,:,1) * p%velocity%data4d(:,:,:,1)
              DO l=2,phys%VDIM
                this%dynvis(:,:,:) = this%dynvis(:,:,:) + this%ephir%data4d(:,:,:,l) &
                                        * p%velocity%data4d(:,:,:,l)
              END DO
              ! use either speed of sound or
              this%dynvis(:,:,:) = etafkt_alpha(this%dynconst,p%density%data3d(:,:,:), &
                phys%bccsound%data3d(:,:,:),this%dynvis(:,:,:)+Mesh%Omega)
            END SELECT
          END SELECT
       CASE(BETA)
          ! Duschl type beta viscosity kin_vis = beta * spec_angular_momentum
          SELECT TYPE(phys => Physics)
          CLASS IS(physics_eulerisotherm)
            SELECT TYPE(p => pvar)
            CLASS IS(statevector_eulerisotherm)
              ! project velocity on ephi/r -> local angular velocity
              ! use dynvis as temporary storage
              this%dynvis(:,:,:) = this%ephir%data4d(:,:,:,1) * p%velocity%data4d(:,:,:,1)
              DO l=2,phys%VDIM
                this%dynvis(:,:,:) = this%dynvis(:,:,:) + this%ephir%data4d(:,:,:,l) &
                                       * p%velocity%data4d(:,:,:,l)
              END DO
              ! compute dynamic viscosity using beta ansatz; account for rotating
              ! non-inertial frames by adding the frame angular velocity
              this%dynvis(:,:,:) = etafkt_beta(this%dynconst,Mesh%radius%bcenter(:,:,:), &
                p%density%data3d(:,:,:),this%dynvis(:,:,:)+Mesh%Omega)
            END SELECT
          END SELECT
       CASE(PRINGLE) ! constant kinematic viscosity
          SELECT TYPE(phys => Physics)
          CLASS IS(physics_eulerisotherm)
            SELECT TYPE(p => pvar)
            CLASS IS(statevector_eulerisotherm)
              this%dynvis(:,:,:) = etafkt_pringle(this%dynconst,p%density%data3d(:,:,:))
            END SELECT
          END SELECT
! TODO: height of the disk is calculated in another source module, which is not translated yet. Therefore, ALPHA_ALT is not
! working
!        CASE(ALPHA_ALT)
!          ! eta = nu*rho = alpha*cs*h * rho
!          ! compute dynamic viscosity
!          this%dynvis(:,:,:) = this%dynconst * Physics%bccsound%data3d(:,:,:) &
!                * Physics%sources%height(:,:,:) * pvar(:,:,:,Physics%DENSITY)
       END SELECT

       IF(this%use_envelope.EQ.1) &
         this%dynvis(:,:,:) = this%envelope(:,:,:) * this%dynvis(:,:,:)

       ! Set the bulk viscosity
       SELECT CASE(this%viscosity%GetType())
       CASE(MOLECULAR)
         ! do nothing, since it has already been initialized
         ! in InitSources_viscosity
       CASE(ALPHA,BETA,PRINGLE,ALPHA_ALT)
         ! All available parametrized viscosities should be trace free.
         ! This can be achieved by setting the following:
         this%bulkvis(:,:,:) = -2./3.*this%dynvis(:,:,:)
       END SELECT

       ! update time
       this%time = time
    END IF
  CONTAINS
    ! some elemental functions for computation of the viscosity

    ! Alpha viscosity
    ELEMENTAL FUNCTION etafkt_alpha(alpha,density,cs,omega) RESULT(eta)
      IMPLICIT NONE
      !----------------------------------------------------------------------!
      REAL, INTENT(IN) :: alpha,density,cs,omega
      REAL :: eta
      !----------------------------------------------------------------------!
      eta = alpha * density * cs**2 / ABS(omega)
    END FUNCTION etafkt_alpha

    ! Beta viscosity
    ELEMENTAL FUNCTION etafkt_beta(beta,r,density,omega) RESULT(eta)
      IMPLICIT NONE
      !----------------------------------------------------------------------!
      REAL, INTENT(IN) :: beta,r,density,omega
      REAL :: eta
      !----------------------------------------------------------------------!
      ! nu  = beta * r * v_phi = beta * r^2 * omega
      ! eta = rho * nu
      eta = beta * density * r**2 * ABS(omega)
    END FUNCTION etafkt_beta

    ! Pringle disk (kinematic viscosity is constant)
    ELEMENTAL FUNCTION etafkt_pringle(nu,rho) RESULT(eta)
      IMPLICIT NONE
      !----------------------------------------------------------------------!
      REAL, INTENT(IN) :: nu,rho
      REAL :: eta
      !----------------------------------------------------------------------!
      eta = nu * rho   !nu is the kinematic viscosity
    END FUNCTION etafkt_pringle

  END SUBROUTINE UpdateViscosity


  SUBROUTINE ExternalSources_single(this,Mesh,Physics,Fluxes,Sources,time,dt,pvar,cvar,sterm)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(sources_viscosity),INTENT(INOUT) :: this
    CLASS(mesh_base),INTENT(IN)            :: Mesh
    CLASS(physics_base),INTENT(INOUT)      :: Physics
    CLASS(fluxes_base),INTENT(IN)          :: Fluxes
    CLASS(sources_base), INTENT(INOUT)  :: Sources
    REAL,INTENT(IN)                        :: time, dt
    CLASS(marray_compound),INTENT(INOUT)   :: pvar,cvar,sterm
    !------------------------------------------------------------------------!
    CALL this%UpdateViscosity(Mesh,Physics,Fluxes,time,pvar,cvar)
    CALL Physics%CalcStresses_euler(Mesh,pvar%data4d,this%dynvis,this%bulkvis, &
             this%btxx,this%btxy,this%btxz,this%btyy,this%btyz,this%btzz)
    CALL Physics%ViscositySources(Mesh,pvar%data4d,this%btxx,this%btxy,this%btxz, &
             this%btyy,this%btyz,this%btzz,sterm%data4d)
  END SUBROUTINE ExternalSources_single


  SUBROUTINE CalcTimestep_single(this,Mesh,Physics,Fluxes,pvar,cvar,time,dt)
    USE physics_eulerisotherm_mod, ONLY : physics_eulerisotherm, statevector_eulerisotherm
    USE physics_euler_mod, ONLY : physics_euler, statevector_euler
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(Sources_viscosity),INTENT(INOUT) :: this
    CLASS(Mesh_base),INTENT(IN)         :: Mesh
    CLASS(Physics_base),INTENT(INOUT)   :: Physics
    CLASS(Fluxes_base),INTENT(IN)       :: Fluxes
    CLASS(marray_compound), INTENT(INOUT) :: pvar,cvar
    REAL, INTENT(IN)                      :: time
    REAL, INTENT(OUT)                     :: dt
    !------------------------------------------------------------------------!
    REAL              :: invdt_x, invdt_y,invdt_z
    !------------------------------------------------------------------------!
    ! update dynamic and bulk viscosity
    CALL this%UpdateViscosity(Mesh,Physics,Fluxes,time,pvar,cvar)

    ! compute kinematic viscosity
    SELECT TYPE(p => pvar)
    CLASS IS(statevector_eulerisotherm)
      this%kinvis(:,:,:) = this%dynvis(:,:,:) / p%density%data3d(:,:,:)
    END SELECT

    ! x-direction
    IF (Mesh%INUM.GT.1) THEN
       invdt_x = MAXVAL(this%kinvis(:,:,:) / Mesh%dlx%data3d(:,:,:)**2, &
                        MASK=Mesh%without_ghost_zones%mask3d(:,:,:))
    ELSE
       ! set to zero, i.e. no limit in x-direction due to diffusion
       invdt_x = 0.0
    END IF
    ! y-direction
    IF (Mesh%JNUM.GT.1) THEN
       invdt_y = MAXVAL(this%kinvis(:,:,:)  / Mesh%dly%data3d(:,:,:)**2, &
                        MASK=Mesh%without_ghost_zones%mask3d(:,:,:))
    ELSE
       ! set to zero, i.e. no limit in y-direction due to diffusion
       invdt_y = 0.0
    END IF
    ! z-direction
    IF (Mesh%INUM.GT.1) THEN
       invdt_z = MAXVAL(this%kinvis(:,:,:)  / Mesh%dlz%data3d(:,:,:)**2, &
                        MASK=Mesh%without_ghost_zones%mask3d(:,:,:))
    ELSE
       ! set to zero, i.e. no limit in z-direction due to diffusion
       invdt_z = 0.0
    END IF
    ! largest time step due to diffusion
    invdt_x = MAX(invdt_x, invdt_y,invdt_z)
    IF (invdt_x.GT.TINY(invdt_x)) THEN
       dt = this%cvis / invdt_x
    ELSE
       dt = HUGE(dt)
    END IF
  END SUBROUTINE CalcTimestep_single


  SUBROUTINE Finalize(this)
    IMPLICIT NONE
    !------------------------------------------------------------------------!
    CLASS(Sources_viscosity),INTENT(INOUT) :: this
    !------------------------------------------------------------------------!
    IF (ALLOCATED(this%ephir)) THEN
      CALL this%ephir%Destroy()
      DEALLOCATE(this%ephir)
    END IF
    DEALLOCATE(this%dynvis,this%kinvis,this%bulkvis, &
               this%btxx,this%btyy,this%btzz,this%btxy,this%btxz,this%btyz)
    IF(this%viscosity%GetType().EQ.ALPHA) DEALLOCATE(this%invr)
    IF(this%use_envelope.EQ.1) DEALLOCATE(this%envelope)
    CALL this%Finalize_base()
    IF(ASSOCIATED(this%next)) CALL this%next%Finalize()
  END SUBROUTINE Finalize


END MODULE sources_viscosity_mod
