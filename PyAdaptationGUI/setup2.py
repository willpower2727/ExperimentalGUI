#setup file for generating executable of the GUI
from distutils.core import setup
import py2exe
import matplotlib
import FileDialog
import numpy
import scipy

setup(windows=['PyAdaptationGUI.py'],
      data_files=matplotlib.get_py2exe_datafiles(),
      options={"py2exe":{"includes": ["FileDialog","scipy.special._ufuncs_cxx","scipy.integrate","scipy.sparse.csgraph._validation"]}})

