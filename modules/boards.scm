;; ChromeOS Board Hardware Database
;;
;; Purpose: Define hardware characteristics for each ChromeOS board
;;
;; UNTESTED — Syntax valid in Guile, needs Guix modules
;;
;; This module provides board-specific configuration for:
;; - WiFi kernel modules
;; - CPU type (intel/amd/arm)
;; - GPU type for graphics drivers
;; - Thermal management approach

(define-module (boards)
  #:export (%board-db))

(define %board-db
  `(
    ;; Intel boards (Jasper Lake / Apollo Lake / Alder Lake / Gemini Lake)
    ;; All use Intel WiFi (AX201/AX210), Intel GPU, require intel_pstate
    (dedede . ((cpu . intel)
               (gpu . intel)
               (wifi . intel)
               (wifi-modules . ("iwlmvm" "ccm"))
               (kernel . "5.4+")
               (audio . #f)
               (touchscreen . #t)
               (power-management . intel-pstate)
               (thermal . thermald)))

    (octopus . ((cpu . intel)
                (gpu . intel)
                (wifi . intel)
                (wifi-modules . ("iwlmvm" "ccm"))
                (kernel . "4.14")
                (audio . #t)
                (touchscreen . #t)
                (power-management . intel-pstate)
                (thermal . thermald)))

    (nissa . ((cpu . intel)
              (gpu . intel)
              (wifi . intel)
              (wifi-modules . ("iwlmvm" "ccm"))
              (kernel . "5.10+")
              (audio . #f)
              (touchscreen . #t)
              (power-management . intel-pstate)
              (thermal . thermald)))

    (hatch . ((cpu . intel)
              (gpu . intel)
              (wifi . intel)
              (wifi-modules . ("iwlmvm" "ccm"))
              (kernel . "5.4")
              (audio . #f)
              (power-management . intel-pstate)
              (thermal . thermald)))

    (brya . ((cpu . intel)
             (gpu . intel)
             (wifi . intel)
             (wifi-modules . ("iwlmvm" "ccm"))
             (kernel . "5.10+")
             (audio . #f)
             (touchscreen . #f)
             (power-management . intel-pstate)
             (thermal . thermald)))

    (snappy . ((cpu . intel)
               (gpu . intel)
               (wifi . intel)
               (wifi-modules . ("iwlmvm" "ccm"))
               (kernel . "5.4")
               (audio . #t)
               (touchscreen . #t)
               (power-management . intel-pstate)
               (thermal . thermald)))

    ;; AMD boards (Ryzen / Stoney Ridge)
    ;; Use AMD GPU, MediaTek or Realtek WiFi, different power management
    (zork . ((cpu . amd)
             (gpu . amd)
             (wifi . mediatek)
             (wifi-modules . ("mt7921e"))
             (kernel . "5.4")
             (audio . #f)
             (power-management . amd-pstate)
             (thermal . #f)))

    (grunt . ((cpu . amd)
              (gpu . amd)
              (wifi . realtek)
              (wifi-modules . ())
              (kernel . "4.14")
              (audio . #f)
              (power-management . amd-pstate)
              (thermal . #f)))

    ;; ARM boards (MediaTek / Qualcomm)
    ;; Use Mali/Adreno GPU, ARM-specific power management
    (jacuzzi . ((cpu . arm)
                (gpu . mali)
                (wifi . mediatek)
                (wifi-modules . ())
                (kernel . "5.4")
                (audio . #f)
                (power-management . cpufreq)
                (thermal . #f)))

    (corsola . ((cpu . arm)
                (gpu . mali)
                (wifi . mediatek)
                (wifi-modules . ())
                (kernel . "5.15")
                (audio . #f)
                (power-management . cpufreq)
                (thermal . #f)))

    (hana . ((cpu . arm)
             (gpu . mali)
             (wifi . mediatek)
             (wifi-modules . ())
             (kernel . "5.4")
             (audio . #f)
             (touchscreen . #f)
             (webcam . #f)
             (power-management . cpufreq)
             (thermal . #f)))

    (trogdor . ((cpu . arm)
                (gpu . adreno)
                (wifi . qualcomm)
                (wifi-modules . ("ath10k_pci" "ath10k_core"))
                (kernel . "5.4")
                (audio . #f)
                (power-management . cpufreq)
                (thermal . #f)))))

(define-public (get-board-config board)
  "Return configuration alist for BOARD symbol."
  (assoc-ref %board-db board))

(define-public (board-cpu board)
  "Return CPU type for BOARD."
  (assoc-ref (get-board-config board) 'cpu))

(define-public (board-wifi-modules board)
  "Return list of WiFi kernel modules for BOARD."
  (assoc-ref (get-board-config board) 'wifi-modules))