import os
import shutil
from src.work_timer import backup_config, load_config, save_config, PUBLIC_HOLIDAYS, export_holidays_to_csv, CONFIG_FILE

def main():
    # backup existing config
    bkp = backup_config()
    orig_cfg = load_config()

    try:
        # write PUBLIC_HOLIDAYS into config
        cfg = orig_cfg.copy() if isinstance(orig_cfg, dict) else {'name': '', 'holidays': {}}
        cfg['holidays'] = PUBLIC_HOLIDAYS.copy()
        save_config(cfg)

        # perform export
        export_holidays_to_csv('test_export_holidays.csv', date_style='display')

    finally:
        # restore original config: if backup exists, use it; otherwise rewrite original dict
        if bkp and os.path.exists(bkp):
            try:
                os.replace(bkp, CONFIG_FILE)
                print('Original config restored from backup.')
            except Exception as e:
                print('Failed to restore backup:', e)
        else:
            try:
                save_config(orig_cfg)
                print('Original config restored.')
            except Exception as e:
                print('Failed to restore original config:', e)

if __name__ == '__main__':
    main()
