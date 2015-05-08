#cython: embedsignature=True

cimport cython
from libcpp cimport bool

cimport Clipper as c

cimport numpy as cnp
import numpy as np

from libc.stdio cimport *


#np.import_array()
cnp.import_array()

cdef extern from "numpy/ndarraytypes.h" nogil:
  int NPY_ARRAY_CARRAY

cimport cpython.ref as ref



#enum ClipType
ctIntersection      = c.ctIntersection
ctUnion             = c.ctUnion
ctDifference        = c.ctDifference
ctXor               = c.ctXor
#enum PolyType
ptSubject           = c.ptSubject
ptClip              = c.ptClip
#enum PolyFillType
pftEvenOdd          = c.pftEvenOdd
pftNonZero          = c.pftNonZero
pftPositive         = c.pftPositive
pftNegative         = c.pftNegative
#enum InitOptions
ioReverseSolution   = c.ioReverseSolution
ioStrictlySimple    = c.ioStrictlySimple
ioPreserveCollinear = c.ioPreserveCollinear
#enum JoinType
jtSquare            = c.jtSquare
jtRound             = c.jtRound
jtMiter             = c.jtMiter
#enum EndType
etClosedPolygon     = c.etClosedPolygon
etClosedLine        = c.etClosedLine
etOpenButt          = c.etOpenButt
etOpenSquare        = c.etOpenSquare
etOpenRound         = c.etOpenRound

cdef class ClipperPathsIterator:
  cdef ClipperPaths paths
  cdef unsigned int current
  
  def __cinit__(self, ClipperPaths p):
    self.paths   = p
    self.current = 0
    
  @cython.boundscheck(False)
  def __next__(self):
    if self.current >= self.paths.thisptr[0].size():
      raise StopIteration
    else:
      x = Path2arrayView(self.paths, &self.paths.thisptr[0][self.current])
      self.current += 1
      return x


@cython.boundscheck(False)
def arrayListToClipperPaths(list paths, ClipperPaths output=None):
  """Convert a list of two-dimensional arrays of type int64 to a ClipperPaths 
  object (this list can be got with list(x for x in paths)"""
  cdef c.Path *path
  cdef unsigned int k, p, npaths, npoints
  cdef cnp.ndarray[cnp.int64_t, ndim=1] array
  if output is None:
    output = ClipperPaths()
  npaths = len(paths)
  output.thisptr[0].resize(npaths)
  for k in range(npaths):
    array   = paths[k]
    npoints = array.shape[0]
    path    = &output.thisptr[0][k]
    path[0].resize(npoints)
    for p in range(npoints):
      path[0][p].X = array[p,0]
      path[0][p].Y = array[p,1]
    

cdef class ClipperPaths:
  """Thin wrapper around Clipper::Paths. It is intended just as a temporary object
  to do Clipper operations on the data, the end results to be incorporated back
  into a SlicedModel"""

  def __cinit__(self):       self.thisptr = new c.Paths()
  def __dealloc__(self): del self.thisptr

  def __reduce__(self):
    d = {'state': list(self.__iter__())}
    return (ClipperPaths, (), d)
  def __setstate__(self, d):
    arrayListToClipperPaths(d['state'], self)
    
  def __len__(self):
    return self.thisptr[0].size()
  def __iter__(self):
    return ClipperPathsIterator(self)
  
  def __getitem__(self, val):
    """Basic indexing support"""
    cdef int npath
    if   isinstance(val, int):
      npath = val
      if (npath<0) or (<unsigned int>npath>=self.thisptr[0].size()):
        raise Exception('Invalid index')
      return Path2arrayView(self.paths, &self.thisptr[0][npath])
    elif isinstance(val, slice) or isinstance(val, tuple):
      raise Exception('This object does not support slicing, only indexing')
    else:
      raise IndexError('Invalid slice object')
  
  def clear(self):
    self.thisptr[0].clear()
  
  def reverse(self):
    c.ReversePaths(self.thisptr[0])
  
  cdef c.Paths * _simplify(self, c.Paths *out, c.PolyFillType fillType=c.pftEvenOdd) nogil:
    if out==NULL:
      out = new c.Paths()
    c.SimplifyPolygons(self.thisptr[0], out[0], fillType)
    return out
  
  def simplify(self, int fillType=c.pftEvenOdd):
    cdef ClipperPaths out = ClipperPaths()
    out.thisptr = self._simplify(out.thisptr, <c.PolyFillType>fillType)
    return out

  def simplifyInPlace(self, int fillType=c.pftEvenOdd):
    c.SimplifyPolygons(self.thisptr[0], <c.PolyFillType>fillType)
  
  cdef c.Paths * _clean(self, c.Paths *out, double distance=1.415) nogil:
    if out==NULL:
      out = new c.Paths()
    c.CleanPolygons(self.thisptr[0], out[0], distance)
    return out
  
  def clean(self, double distance=1.415):
    cdef ClipperPaths out = ClipperPaths()
    out.thisptr = self._clean(out.thisptr, distance)
    return out

  def   cleanInPlace(self, double distance=1.415):
    c.CleanPolygons(self.thisptr[0], distance)
  
  @cython.boundscheck(False)
  def orientation(self, unsigned int npath):
    if npath>=self.thisptr[0].size():
      raise Exception('Invalid index')
    return c.Orientation(self.thisptr[0][npath])
    
  @cython.boundscheck(False)
  def orientations(self):
    cdef cnp.npy_intp length = self.thisptr[0].size()
    #using cnp.uint8_t is an ugly hack, but there is no cnp.bool_t
    cdef cnp.ndarray out = cnp.PyArray_EMPTY(1, &length, cnp.NPY_BOOL, 0)
    cdef unsigned int k
    for k in range(length):
      out[k] = c.Orientation(self.thisptr[0][k])
    return out
  
  @cython.boundscheck(False)
  def area(self, unsigned int npath):
    if npath>=self.thisptr[0].size():
      raise Exception('Invalid index')
    return c.Area(self.thisptr[0][npath])
    
  @cython.boundscheck(False)
  def areas(self):
    cdef cnp.npy_intp length = self.thisptr[0].size()
    cdef cnp.ndarray[cnp.float64_t, ndim=1] out = cnp.PyArray_EMPTY(1, &length, cnp.NPY_FLOAT64, 0)
    cdef unsigned int k
    for k in range(length):
      out[k] = c.Area(self.thisptr[0][k])
    return out

  @cython.boundscheck(False)
  def pointInPolygon(self, unsigned int npath, int x, int y):
    if npath>=self.thisptr[0].size():
      raise Exception('Invalid index')
    cdef c.IntPoint p
    p.X = x
    p.Y = y
    return c.PointInPolygon(p, self.thisptr[0][npath])
  
cdef class ClipperPolyTree:
  """Thin wrapper around Clipper::PolyTree. It is intended just as a temporary object
  to do Clipper operations on the data, the end results to be incorporated back
  into a SlicedModel"""

  def __cinit__(self):       self.thisptr = new c.PolyTree()
  def __dealloc__(self): del self.thisptr

  def clear(self):
    self.thisptr[0].Clear()
    
  cdef c.Paths *toPaths(self, c.Paths *output=NULL):
    if output==NULL:
      output = new c.Paths()
    else:
      output[0].clear()
    c.PolyTreeToPaths(self.thisptr[0], output[0])
    return output

  def toClipperPaths(self, ClipperPaths paths=None):
    if paths is None:
      paths                 = ClipperPaths()
    paths.thisptr           = self.toPaths(paths.thisptr)
    return paths
  
  def toClipperPathsByType(self, bool closed):
    cdef ClipperPaths paths = ClipperPaths()
    if closed:
      c.ClosedPathsFromPolyTree(self.thisptr[0], paths.thisptr[0])
    else:
      c.OpenPathsFromPolyTree(self.thisptr[0], paths.thisptr[0])
    return paths
    


cdef class ClipperClip:
  """Thin wrapper around Clipper::Clipper, to do operations with ClipperPaths"""

  property reverseSolution:
    def __get__(self):    return self.thisptr[0].ReverseSolution()
    def __set__(self, bool val): self.thisptr[0].ReverseSolution(val)

  property strictlySimple:
    def __get__(self):    return self.thisptr[0].StrictlySimple()
    def __set__(self, bool val): self.thisptr[0].StrictlySimple(val)

  property preserveCollinear:
    def __get__(self):    return self.thisptr[0].PreserveCollinear()
    def __set__(self, bool val): self.thisptr[0].PreserveCollinear(val)

  property subjectFillType:
    def __get__(self):   return self.subjectfill
    def __set__(self, int val): self.subjectfill = <c.PolyFillType>val

  property clipFillType:
    def __get__(self):   return self.clipfill
    def __set__(self, int val): self.clipfill    = <c.PolyFillType>val

  property clipType:
    def __get__(self):   return self.cliptype
    def __set__(self, int val): self.cliptype    = <c.ClipType>val

  def __cinit__  (self, int clipType=c.ctIntersection, int clipFillType=c.pftEvenOdd, int subjectFillType=c.pftEvenOdd, bool reverseSolution=False, bool strictlySimple=False, bool preserveCollinear=False):
    self.thisptr = new c.Clipper()
    self.subjectfill = <c.PolyFillType>subjectFillType
    self.clipfill    = <c.PolyFillType>clipFillType
    self.cliptype    = <c.ClipType>    clipType
    if strictlySimple:
      self.thisptr[0].StrictlySimple   (True)
    if reverseSolution:
      self.thisptr[0].ReverseSolution  (True)
    if preserveCollinear:
      self.thisptr[0].PreserveCollinear(True)
    
  def __dealloc__(self): del self.thisptr

  cpdef bool AddPaths   (self, ClipperPaths paths, c.PolyType typ, bool pathsAreClosed=True): return self.thisptr[0].AddPaths(paths.thisptr[0], typ,         pathsAreClosed)
  def        AddSubjects(self, ClipperPaths paths,                 bool pathsAreClosed=True): return self.           AddPaths(paths,            c.ptSubject, pathsAreClosed)
  def        AddClips   (self, ClipperPaths paths                                          ): return self.           AddPaths(paths,            c.ptClip,    True)
  
  def clear(self):
    self.thisptr[0].Clear()

  cpdef bool ExecuteWithPaths   (self, ClipperPaths    solution):
    return self.thisptr[0].Execute(self.cliptype, solution.thisptr[0], self.subjectfill, self.clipfill)

  cpdef bool ExecuteWithPolyTree(self, ClipperPolyTree solution):
    return self.thisptr[0].Execute(self.cliptype, solution.thisptr[0], self.subjectfill, self.clipfill)
    
  def        Execute            (self, object          solution):
    if   isinstance(solution, ClipperPaths   ): return self.ExecuteWithPaths   (<ClipperPaths>   solution)
    elif isinstance(solution, ClipperPolyTree): return self.ExecuteWithPolyTree(<ClipperPolyTree>solution)
    else                                      : raise ValueError('Object of incorrect type: '+type(solution))



cdef class ClipperOffset:
  """Thin wrapper around Clipper::ClipperOffset, to do operations with ClipperPaths"""

  property miterLimit:
    def __get__(self):      return self.thisptr[0].MiterLimit
    def __set__(self, double val): self.thisptr[0].MiterLimit   = val

  property arcTolerance:
    def __get__(self):      return self.thisptr[0].ArcTolerance
    def __set__(self, double val): self.thisptr[0].ArcTolerance = val

  property delta:
    def __get__(self):      return self._delta
    def __set__(self, double val): self._delta = val

  def __cinit__  (self, double miterLimit=3.0, double arcTolerance=3.0, double delta=1.0):
    self.thisptr                 = new c.ClipperOffset()
    self._delta                  = delta
    self.thisptr[0].MiterLimit   = miterLimit
    self.thisptr[0].ArcTolerance = arcTolerance
  def __dealloc__(self): del self.thisptr

  def AddPaths(self, ClipperPaths paths, int joinType=c.jtRound, int endType=c.etClosedPolygon):
    self.thisptr[0].AddPaths(paths.thisptr[0], <c.JoinType>joinType, <c.EndType>endType)

  def clear(self):
    self.thisptr[0].Clear()

  cpdef ExecuteWithPaths   (self, ClipperPaths    solution):
    self.thisptr[0].Execute(solution.thisptr[0], self._delta)

  cpdef ExecuteWithPolyTree(self, ClipperPolyTree solution):
    self.thisptr[0].Execute(solution.thisptr[0], self._delta)

  def   Execute            (self, object          solution):
    if   isinstance(solution, ClipperPaths   ): self.ExecuteWithPaths   (<ClipperPaths>   solution)
    elif isinstance(solution, ClipperPolyTree): self.ExecuteWithPolyTree(<ClipperPolyTree>solution)
    else                                      : raise ValueError('Object of incorrect type: '+type(solution))


#strides have to be computed just once
cdef cnp.npy_intp *pointstrides = [sizeof(c.IntPoint),
                                   <cnp.uint8_t*>&(<c.IntPoint*>NULL).Y - 
                                   <cnp.uint8_t*>&(<c.IntPoint*>NULL).X]

cdef cnp.ndarray Path2arrayView(ClipperPaths parent, c.Path *path):
  """Similar to Polygon2arrayI, but instead of allocating a full-blown array,
  the returned array is a view into the underlying data"""
  cdef void         *data  = &(path[0][0].X)
  cdef cnp.npy_intp *dims  = [path[0].size(),2]
  cdef cnp.ndarray  result = cnp.PyArray_New(np.ndarray, 2, dims, cnp.NPY_INT64, pointstrides,
                                             data, -1, NPY_ARRAY_CARRAY, <object>NULL)
  ##result.base is of type PyObject*, so no reference counting with this assignment
  result.base              = <ref.PyObject*>parent
  ref.Py_INCREF(parent) #so, make sure that "result" owns a reference to "parent"
  #ref.Py_INCREF(result)
  return result
  